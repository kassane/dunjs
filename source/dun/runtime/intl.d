module dun.runtime.intl;


/++
 + `@trusted policy`: ECMA-402 (Intl) installer. `@trusted` is for
 + the install-time `engine.eval` of the Intl polyfill source.
 + On V8 the polyfill is a no-op (V8 ships Intl natively); on QJS /
 + JSC the polyfill provides a basic subset.
 +/
import dun.engine.iface : IJSEngine;

void installIntl(IJSEngine engine) @trusted
{
    assert(engine !is null);
    auto global = engine.getGlobal();
    auto existing = engine.getProperty(global, "Intl");
    scope(exit) engine.freeValue(global);

    // The D-side check of `globalThis.Intl` can race with V8's lazy
    // installation, returning `undefined` even though the engine
    // exposes Intl by the time user code runs. So we ALWAYS try the
    // compare-bind fixup: if Intl really doesn't exist when the JS
    // eval runs, the early `typeof Intl === 'undefined'` guard makes
    // it a no-op.
    {
        // Force V8 to initialize Intl now (it lazy-loads on first
        // reference), then patch the Collator/Format prototypes.
        // The `new Intl.Collator()` in the source triggers init.
        auto fixupRes = engine.eval(intlCollatorBindCompareSource(),
            "<intl-collator-bind-compare>");
        if (!fixupRes.isError) engine.freeValue(fixupRes.value);
    }

    if (!engine.isUndefined(existing) && engine.isObject(existing))
    {
        engine.freeValue(existing);
        return;
    }
    engine.freeValue(existing);

    auto result = engine.eval(intlPolyfillSource(), "<intl>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("Intl polyfill init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }
    engine.freeValue(result.value);
}

string intlCollatorBindCompareSource() pure nothrow @safe
{
    // Convert `Intl.Collator.prototype.compare` from a regular method
    // (V8 without ICU) to a getter that returns a bound function (spec
    // behavior). This makes `const { compare } = new Intl.Collator()`
    // work the same as on Node/Bun/Deno.
    //
    // We also wrap `localeCompare` on String.prototype so destructuring
    // patterns that go through the prototype path don't crash either.
    // CAUTION: every line of this string is concatenated with `~` so
    // there are NO newlines between them at runtime. JS `//` comments
    // would swallow the rest of the source. Use `/* */` only.
    return
    "(function() {" ~
    "try {" ~
    "  if (typeof Intl === 'undefined' || !Intl.Collator) return;" ~
    "  /* Force V8 to materialize Intl.Collator.prototype now. */" ~
    "  new Intl.Collator();" ~
    "  var proto = Intl.Collator.prototype;" ~
    "  if (!proto) return;" ~
    "  var origCompare = proto.compare;" ~
    "  if (typeof origCompare !== 'function') return;" ~
    "  Object.defineProperty(proto, 'compare', {" ~
    "    configurable: true," ~
    "    get: function() {" ~
    "      var self = this;" ~
    "      return function(x, y) { return origCompare.call(self, x, y); };" ~
    "    }" ~
    "  });" ~
    "  if (Intl.NumberFormat && Intl.NumberFormat.prototype.format) {" ~
    "    var origFmt = Intl.NumberFormat.prototype.format;" ~
    "    Object.defineProperty(Intl.NumberFormat.prototype, 'format', {" ~
    "      configurable: true," ~
    "      get: function() {" ~
    "        var self = this;" ~
    "        return function(v) { return origFmt.call(self, v); };" ~
    "      }" ~
    "    });" ~
    "  }" ~
    "  if (Intl.DateTimeFormat && Intl.DateTimeFormat.prototype.format) {" ~
    "    var origDtf = Intl.DateTimeFormat.prototype.format;" ~
    "    Object.defineProperty(Intl.DateTimeFormat.prototype, 'format', {" ~
    "      configurable: true," ~
    "      get: function() {" ~
    "        var self = this;" ~
    "        return function(v) { return origDtf.call(self, v); };" ~
    "      }" ~
    "    });" ~
    "  }" ~
    "} catch (e) {}" ~
    "})();";
}

private string intlPolyfillSource() pure nothrow @safe
{
    return "(function() {" ~
    "if (typeof globalThis.Intl !== 'undefined') return;" ~

    "var Intl = {};" ~

    // Intl.getCanonicalLocales
    "Intl.getCanonicalLocales = function(locales) {" ~
    "  if (typeof locales === 'string') return [locales];" ~
    "  if (Array.isArray(locales)) return locales.slice();" ~
    "  return [];" ~
    "};" ~

    "Intl.supportedValuesOf = function(key) {" ~
    "  if (key === 'calendar') return ['gregory','iso8601','buddhist','chinese','japanese'];" ~
    "  if (key === 'collation') return ['default'];" ~
    "  if (key === 'currency') return ['USD','EUR','GBP','JPY','CNY','KRW','INR','BRL','CAD','AUD','CHF'];" ~
    "  if (key === 'numberingSystem') return ['latn','arab','hans','deva'];" ~
    "  if (key === 'timeZone') return ['UTC','America/New_York','America/Chicago','America/Denver','America/Los_Angeles','Europe/London','Europe/Paris','Europe/Berlin','Asia/Tokyo','Asia/Shanghai','Asia/Kolkata','Australia/Sydney'];" ~
    "  if (key === 'unit') return ['acre','byte','celsius','centimeter','day','degree','fahrenheit','foot','gallon','gigabit','gigabyte','gram','hectare','hour','inch','kilobit','kilobyte','kilogram','kilometer','liter','megabit','megabyte','meter','mile','milliliter','millimeter','millisecond','minute','month','ounce','percent','petabyte','pound','second','stone','terabit','terabyte','week','yard','year'];" ~
    "  throw new RangeError('Invalid key: ' + key);" ~
    "};" ~

    // Intl.Locale
    "Intl.Locale = function Locale(tag, opts) {" ~
    "  if (typeof tag !== 'string') throw new TypeError('Invalid language tag');" ~
    "  opts = opts || {};" ~
    "  var parts = tag.split('-');" ~
    "  this.language = parts[0] || 'en';" ~
    "  this.script = parts.length > 2 ? parts[1] : undefined;" ~
    "  this.region = parts.length > 1 ? parts[parts.length-1].toUpperCase() : undefined;" ~
    "  if (this.region && this.region.length !== 2) this.region = undefined;" ~
    "  this.baseName = tag;" ~
    "  this.calendar = opts.calendar || undefined;" ~
    "  this.numberingSystem = opts.numberingSystem || undefined;" ~
    "  this.hourCycle = opts.hourCycle || undefined;" ~
    "};" ~
    "Intl.Locale.prototype.toString = function() { return this.baseName; };" ~
    "Intl.Locale.prototype.maximize = function() { return new Intl.Locale(this.baseName); };" ~
    "Intl.Locale.prototype.minimize = function() { return new Intl.Locale(this.language); };" ~

    // Shared resolvedOptions helper
    "function resolveLocale(locales) {" ~
    "  if (typeof locales === 'string') return locales;" ~
    "  if (Array.isArray(locales) && locales.length > 0) return String(locales[0]);" ~
    "  return 'en';" ~
    "}" ~

    // Intl.DateTimeFormat
    "Intl.DateTimeFormat = function DateTimeFormat(locales, options) {" ~
    "  if (!(this instanceof DateTimeFormat)) return new DateTimeFormat(locales, options);" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    "Intl.DateTimeFormat.prototype.format = function(date) {" ~
    "  if (date === undefined) date = new Date();" ~
    "  if (typeof date === 'number') date = new Date(date);" ~
    "  var o = this._options;" ~
    "  if (o.dateStyle || o.timeStyle || Object.keys(o).some(function(k){return['year','month','day','hour','minute','second','weekday','era','timeZoneName'].indexOf(k)>=0;})) {" ~
    "    var parts = [];" ~
    "    if (o.dateStyle === 'full' || o.weekday) { var days=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']; parts.push(days[date.getDay()]); }" ~
    "    if (o.dateStyle || o.year || o.month || o.day) {" ~
    "      var months=['January','February','March','April','May','June','July','August','September','October','November','December'];" ~
    "      var ms = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];" ~
    "      var m = o.month === 'short' || o.dateStyle === 'medium' ? ms[date.getMonth()] : o.month === 'numeric' || o.month === '2-digit' ? String(date.getMonth()+1) : months[date.getMonth()];" ~
    "      if (o.month === '2-digit' && m.length < 2) m = '0' + m;" ~
    "      var d = String(date.getDate()); if (o.day === '2-digit' && d.length < 2) d = '0' + d;" ~
    "      var y = String(date.getFullYear()); if (o.year === '2-digit') y = y.slice(-2);" ~
    "      parts.push(m + ' ' + d + ', ' + y);" ~
    "    }" ~
    "    if (o.dateStyle === 'short') { parts = [(date.getMonth()+1) + '/' + date.getDate() + '/' + date.getFullYear()]; }" ~
    "    if (o.timeStyle || o.hour || o.minute || o.second) {" ~
    "      var h = date.getHours(), mi = date.getMinutes(), s = date.getSeconds();" ~
    "      var hc = o.hourCycle || (o.hour12 === false ? 'h23' : 'h12');" ~
    "      var ampm = '';" ~
    "      if (hc === 'h12') { ampm = h >= 12 ? ' PM' : ' AM'; h = h % 12 || 12; }" ~
    "      var ts = String(h).padStart(2,'0') + ':' + String(mi).padStart(2,'0');" ~
    "      if (o.second || o.timeStyle === 'medium' || o.timeStyle === 'long') ts += ':' + String(s).padStart(2,'0');" ~
    "      ts += ampm;" ~
    "      parts.push(ts);" ~
    "    }" ~
    "    return parts.join(', ');" ~
    "  }" ~
    "  /* Default short date — locale-aware ordering. ja/ko: YYYY/M/D;" ~
    "     en-GB / de / fr / it / es / pt / nl: DD/MM/YYYY or DD.MM.YYYY;" ~
    "     en-US / default: M/D/YYYY (no leading zero — matches V8 i18n default). */" ~
    "  var m2=date.getMonth()+1,d2=date.getDate(),y2=date.getFullYear();" ~
    "  var lang2=(this._locale||'').split('-')[0].toLowerCase();" ~
    "  var region2=(this._locale||'').split('-')[1]||'';" ~
    "  if (lang2 === 'ja' || lang2 === 'ko' || lang2 === 'zh' || lang2 === 'hu')" ~
    "    return y2 + '/' + m2 + '/' + d2;" ~
    "  if (lang2 === 'de' || lang2 === 'fi' || lang2 === 'tr' || lang2 === 'cs' || lang2 === 'pl' || lang2 === 'ru')" ~
    "    return (d2<10?'0':'')+d2 + '.' + (m2<10?'0':'')+m2 + '.' + y2;" ~
    "  if (lang2 === 'fr' || lang2 === 'it' || lang2 === 'es' || lang2 === 'pt' || lang2 === 'nl' || lang2 === 'sv' || lang2 === 'da' || lang2 === 'no' || lang2 === 'nb' || (lang2 === 'en' && region2 === 'GB'))" ~
    "    return (d2<10?'0':'')+d2 + '/' + (m2<10?'0':'')+m2 + '/' + y2;" ~
    "  return m2 + '/' + d2 + '/' + y2;" ~
    "};" ~
    "Intl.DateTimeFormat.prototype.formatToParts = function(date) {" ~
    "  var s = this.format(date); return [{type:'literal',value:s}];" ~
    "};" ~
    "Intl.DateTimeFormat.prototype.resolvedOptions = function() {" ~
    "  return Object.assign({locale:this._locale,calendar:'gregory',numberingSystem:'latn',timeZone:'UTC'}, this._options);" ~
    "};" ~
    "Intl.DateTimeFormat.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    // Intl.NumberFormat
    "Intl.NumberFormat = function NumberFormat(locales, options) {" ~
    "  if (!(this instanceof NumberFormat)) return new NumberFormat(locales, options);" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    /* Locale-aware separator table. Maps a language tag prefix to
       {thousands separator, decimal separator}. Covers the common
       European + Asian locales the polyfill bench/test fixtures
       exercise. Real ICU has hundreds of locales; this is the 80/20
       fallback for QJS (which ships no ICU at all). */
    "function _localeSeps(locale) {" ~
    "  if (!locale) return {t:',', d:'.'};" ~
    "  var lang = locale.split('-')[0].toLowerCase();" ~
    "  var region = (locale.split('-')[1] || '').toUpperCase();" ~
    "  /* French / Russian / Polish / Czech / Finnish: NBSP thousand + comma decimal */" ~
    "  if (lang === 'fr' || lang === 'ru' || lang === 'pl' || lang === 'cs' || lang === 'fi' || lang === 'sv' || lang === 'no' || lang === 'nb')" ~
    "    return {t:'\\u00a0', d:','};" ~
    "  /* German / Dutch / Italian / Spanish (mostly) / Portuguese: dot thousand + comma decimal */" ~
    "  if (lang === 'de' || lang === 'nl' || lang === 'it' || lang === 'es' || lang === 'pt' || lang === 'tr' || lang === 'el' || lang === 'da')" ~
    "    return {t:'.', d:','};" ~
    "  /* Indian English: lakhs/crores grouping uses comma; standard decimal dot */" ~
    "  if (lang === 'en' && region === 'IN') return {t:',', d:'.'};" ~
    "  /* English / Chinese / Japanese / Korean / default — comma + dot */" ~
    "  return {t:',', d:'.'};" ~
    "}" ~
    "Intl.NumberFormat.prototype.format = function(num) {" ~
    "  var o = this._options;" ~
    "  var seps = _localeSeps(this._locale);" ~
    "  if (o.style === 'currency') {" ~
    "    var c = o.currency || 'USD';" ~
    "    var sym = {USD:'$',EUR:'\\u20ac',GBP:'\\u00a3',JPY:'\\u00a5',CNY:'\\u00a5',KRW:'\\u20a9',INR:'\\u20b9',BRL:'R$',CAD:'CA$',AUD:'A$',CHF:'CHF'}[c] || c;" ~
    "    var digits = o.maximumFractionDigits !== undefined ? o.maximumFractionDigits : (c === 'JPY' || c === 'KRW' ? 0 : 2);" ~
    "    var n = Number(num).toFixed(digits);" ~
    "    /* Apply locale separators to the currency amount */" ~
    "    if (n.indexOf('.') >= 0) n = n.replace('.', seps.d);" ~
    "    if (o.currencyDisplay === 'code') return c + '\\u00a0' + n;" ~
    "    if (o.currencyDisplay === 'name') return n + ' ' + c;" ~
    "    /* Many locales suffix the currency symbol (de-DE, fr-FR) */" ~
    "    var lang = (this._locale || '').split('-')[0].toLowerCase();" ~
    "    if (lang === 'de' || lang === 'fr' || lang === 'it' || lang === 'es' || lang === 'pt')" ~
    "      return n + '\\u00a0' + sym;" ~
    "    return sym + n;" ~
    "  }" ~
    "  if (o.style === 'percent') return (Number(num) * 100).toFixed(o.maximumFractionDigits || 0) + '%';" ~
    "  if (o.style === 'unit') {" ~
    "    var u = o.unit || '';" ~
    "    var n = typeof o.maximumFractionDigits === 'number' ? Number(num).toFixed(o.maximumFractionDigits) : String(num);" ~
    "    return n + ' ' + u;" ~
    "  }" ~
    "  if (o.notation === 'compact') {" ~
    "    var abs = Math.abs(num);" ~
    "    if (abs >= 1e12) return (num/1e12).toFixed(1) + 'T';" ~
    "    if (abs >= 1e9) return (num/1e9).toFixed(1) + 'B';" ~
    "    if (abs >= 1e6) return (num/1e6).toFixed(1) + 'M';" ~
    "    if (abs >= 1e3) return (num/1e3).toFixed(1) + 'K';" ~
    "    return String(num);" ~
    "  }" ~
    "  var minFrac = o.minimumFractionDigits, maxFrac = o.maximumFractionDigits;" ~
    "  var rawN = typeof maxFrac === 'number' ? Number(num).toFixed(maxFrac)" ~
    "           : typeof minFrac === 'number' ? Number(num).toFixed(minFrac)" ~
    "           : String(num);" ~
    "  var idx = rawN.indexOf('.');" ~
    "  var intPart = idx >= 0 ? rawN.slice(0,idx) : rawN, fracPart = idx >= 0 ? rawN.slice(idx+1) : '';" ~
    "  var neg = intPart[0] === '-'; if (neg) intPart = intPart.slice(1);" ~
    "  /* Grouping: skip when explicitly disabled or for integers < 1000 */" ~
    "  if (o.useGrouping !== false) {" ~
    "    var grouped = '';" ~
    "    for (var i = intPart.length - 1, c = 0; i >= 0; i--, c++) {" ~
    "      if (c > 0 && c % 3 === 0) grouped = seps.t + grouped;" ~
    "      grouped = intPart[i] + grouped;" ~
    "    }" ~
    "    intPart = grouped;" ~
    "  }" ~
    "  return (neg ? '-' : '') + intPart + (fracPart ? seps.d + fracPart : '');" ~
    "};" ~
    "Intl.NumberFormat.prototype.formatToParts = function(num) {" ~
    "  var s = this.format(num); return [{type:'literal',value:s}];" ~
    "};" ~
    "Intl.NumberFormat.prototype.resolvedOptions = function() {" ~
    "  return Object.assign({locale:this._locale,numberingSystem:'latn',style:this._options.style||'decimal'}, this._options);" ~
    "};" ~
    "Intl.NumberFormat.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    // Intl.Collator
    "Intl.Collator = function Collator(locales, options) {" ~
    "  if (!(this instanceof Collator)) return new Collator(locales, options);" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    /* Spec: `compare` is an accessor that returns a function bound to
     * the Collator instance, so `const { compare } = new Intl.Collator()`
     * keeps `this` alive when invoked stand-alone. */
    "Object.defineProperty(Intl.Collator.prototype, 'compare', {" ~
    "  configurable: true," ~
    "  get: function() {" ~
    "    var self = this;" ~
    "    return function(a, b) {" ~
    "      a = String(a); b = String(b);" ~
    "      var sens = (self._options && self._options.sensitivity) || 'variant';" ~
    "      if (sens === 'base' || sens === 'accent') { a = a.toLowerCase(); b = b.toLowerCase(); }" ~
    "      if (a < b) return -1; if (a > b) return 1; return 0;" ~
    "    };" ~
    "  }" ~
    "});" ~
    "Intl.Collator.prototype.resolvedOptions = function() {" ~
    "  return {locale:this._locale,usage:this._options.usage||'sort',sensitivity:this._options.sensitivity||'variant',collation:'default'};" ~
    "};" ~
    "Intl.Collator.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    // Intl.PluralRules
    "Intl.PluralRules = function PluralRules(locales, options) {" ~
    "  if (!(this instanceof PluralRules)) return new PluralRules(locales, options);" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    "Intl.PluralRules.prototype.select = function(n) {" ~
    "  n = Math.abs(Number(n));" ~
    "  if (n === 1) return 'one';" ~
    "  if (n === 0) return 'zero';" ~
    "  if (n === 2) return 'two';" ~
    "  return 'other';" ~
    "};" ~
    "Intl.PluralRules.prototype.resolvedOptions = function() {" ~
    "  return {locale:this._locale,type:this._options.type||'cardinal'};" ~
    "};" ~
    "Intl.PluralRules.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    // Intl.RelativeTimeFormat
    "Intl.RelativeTimeFormat = function RelativeTimeFormat(locales, options) {" ~
    "  if (!(this instanceof RelativeTimeFormat)) return new RelativeTimeFormat(locales, options);" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    "Intl.RelativeTimeFormat.prototype.format = function(value, unit) {" ~
    "  value = Number(value);" ~
    "  if (this._options.numeric === 'auto') {" ~
    "    if (value === -1 && unit === 'day') return 'yesterday';" ~
    "    if (value === 1 && unit === 'day') return 'tomorrow';" ~
    "    if (value === 0) return 'now';" ~
    "  }" ~
    "  var abs = Math.abs(value);" ~
    "  var u = abs === 1 ? unit : unit + 's';" ~
    "  return value < 0 ? abs + ' ' + u + ' ago' : 'in ' + abs + ' ' + u;" ~
    "};" ~
    "Intl.RelativeTimeFormat.prototype.formatToParts = function(value, unit) {" ~
    "  return [{type:'literal',value:this.format(value,unit)}];" ~
    "};" ~
    "Intl.RelativeTimeFormat.prototype.resolvedOptions = function() {" ~
    "  return {locale:this._locale,style:this._options.style||'long',numeric:this._options.numeric||'always'};" ~
    "};" ~
    "Intl.RelativeTimeFormat.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    // Intl.ListFormat
    "Intl.ListFormat = function ListFormat(locales, options) {" ~
    "  if (!(this instanceof ListFormat)) return new ListFormat(locales, options);" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    "Intl.ListFormat.prototype.format = function(list) {" ~
    "  list = Array.from(list).map(String);" ~
    "  if (list.length === 0) return '';" ~
    "  if (list.length === 1) return list[0];" ~
    "  var type = this._options.type || 'conjunction';" ~
    "  var sep = type === 'disjunction' ? ' or ' : type === 'unit' ? ', ' : ' and ';" ~
    "  if (list.length === 2) return list[0] + sep + list[1];" ~
    "  return list.slice(0,-1).join(', ') + ',' + sep + list[list.length-1];" ~
    "};" ~
    "Intl.ListFormat.prototype.formatToParts = function(list) {" ~
    "  return [{type:'literal',value:this.format(list)}];" ~
    "};" ~
    "Intl.ListFormat.prototype.resolvedOptions = function() {" ~
    "  return {locale:this._locale,type:this._options.type||'conjunction',style:this._options.style||'long'};" ~
    "};" ~
    "Intl.ListFormat.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    // Intl.DisplayNames
    "Intl.DisplayNames = function DisplayNames(locales, options) {" ~
    "  if (!(this instanceof DisplayNames)) return new DisplayNames(locales, options);" ~
    "  if (!options || !options.type) throw new TypeError('options.type is required');" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    "Intl.DisplayNames.prototype.of = function(code) {" ~
    "  var t = this._options.type;" ~
    "  if (t === 'language') {" ~
    "    var langs = {en:'English',es:'Spanish',fr:'French',de:'German',ja:'Japanese',zh:'Chinese',ko:'Korean',pt:'Portuguese',ru:'Russian',ar:'Arabic',hi:'Hindi',it:'Italian',nl:'Dutch',sv:'Swedish',pl:'Polish',da:'Danish',fi:'Finnish',nb:'Norwegian',tr:'Turkish'};" ~
    "    return langs[code] || code;" ~
    "  }" ~
    "  if (t === 'region') {" ~
    "    var regions = {US:'United States',GB:'United Kingdom',DE:'Germany',FR:'France',JP:'Japan',CN:'China',KR:'South Korea',BR:'Brazil',IN:'India',AU:'Australia',CA:'Canada',IT:'Italy',ES:'Spain',NL:'Netherlands',SE:'Sweden',RU:'Russia'};" ~
    "    return regions[code] || code;" ~
    "  }" ~
    "  if (t === 'currency') {" ~
    "    var currencies = {USD:'US Dollar',EUR:'Euro',GBP:'British Pound',JPY:'Japanese Yen',CNY:'Chinese Yuan',KRW:'South Korean Won',INR:'Indian Rupee',BRL:'Brazilian Real',CAD:'Canadian Dollar',AUD:'Australian Dollar',CHF:'Swiss Franc'};" ~
    "    return currencies[code] || code;" ~
    "  }" ~
    "  return code;" ~
    "};" ~
    "Intl.DisplayNames.prototype.resolvedOptions = function() {" ~
    "  return {locale:this._locale,type:this._options.type,style:this._options.style||'long',fallback:this._options.fallback||'code'};" ~
    "};" ~
    "Intl.DisplayNames.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    // Intl.Segmenter
    "Intl.Segmenter = function Segmenter(locales, options) {" ~
    "  if (!(this instanceof Segmenter)) return new Segmenter(locales, options);" ~
    "  this._locale = resolveLocale(locales);" ~
    "  this._options = Object.assign({}, options);" ~
    "};" ~
    "Intl.Segmenter.prototype.segment = function(str) {" ~
    "  str = String(str);" ~
    "  var gran = this._options.granularity || 'grapheme';" ~
    "  var segs = [];" ~
    "  if (gran === 'word') {" ~
    "    var re = /[\\w]+|[^\\w]+/g, m;" ~
    "    while ((m = re.exec(str)) !== null) segs.push({segment:m[0],index:m.index,isWordLike:/\\w/.test(m[0])});" ~
    "  } else if (gran === 'sentence') {" ~
    "    var re2 = /[^.!?]+[.!?]?\\s*/g, m2;" ~
    "    while ((m2 = re2.exec(str)) !== null) segs.push({segment:m2[0],index:m2.index});" ~
    "  } else {" ~
    "    for (var i = 0; i < str.length; i++) segs.push({segment:str[i],index:i});" ~
    "  }" ~
    "  segs.containing = function(idx) { for (var i = 0; i < segs.length; i++) if (segs[i].index <= idx && idx < segs[i].index + segs[i].segment.length) return segs[i]; return undefined; };" ~
    "  segs[Symbol.iterator] = function() { var i = 0; return {next:function(){return i < segs.length ? {value:segs[i++],done:false} : {done:true};}}; };" ~
    "  return segs;" ~
    "};" ~
    "Intl.Segmenter.prototype.resolvedOptions = function() {" ~
    "  return {locale:this._locale,granularity:this._options.granularity||'grapheme'};" ~
    "};" ~
    "Intl.Segmenter.supportedLocalesOf = function(locales) { return Intl.getCanonicalLocales(locales); };" ~

    "globalThis.Intl = Intl;" ~

    "Number.prototype.toLocaleString = function(locales, options) {" ~
    "  return new Intl.NumberFormat(locales, options).format(this);" ~
    "};" ~
    "Date.prototype.toLocaleDateString = function(locales, options) {" ~
    "  return new Intl.DateTimeFormat(locales, options).format(this);" ~
    "};" ~
    "Date.prototype.toLocaleTimeString = function(locales, options) {" ~
    "  var o = Object.assign({hour:'2-digit',minute:'2-digit',second:'2-digit'}, options);" ~
    "  return new Intl.DateTimeFormat(locales, o).format(this);" ~
    "};" ~
    "Date.prototype.toLocaleString = function(locales, options) {" ~
    "  var o = Object.assign({year:'numeric',month:'2-digit',day:'2-digit'," ~
    "    hour:'2-digit',minute:'2-digit',second:'2-digit'}, options);" ~
    "  return new Intl.DateTimeFormat(locales, o).format(this);" ~
    "};" ~
    "String.prototype.toLocaleLowerCase = function(locales) { return this.toLowerCase(); };" ~
    "String.prototype.toLocaleUpperCase = function(locales) { return this.toUpperCase(); };" ~
    "String.prototype.localeCompare = function(other, locales, options) {" ~
    "  return new Intl.Collator(locales, options).compare(this, other);" ~
    "};" ~
    "Array.prototype.toLocaleString = function(locales, options) {" ~
    "  return this.map(function(e) { return e != null && typeof e.toLocaleString === 'function' ? e.toLocaleString(locales, options) : String(e); }).join(',');" ~
    "};" ~

    "})()";
}
