/// Security: Permission system and vulnerability auditing.
///
/// Deno-inspired default-deny permission model.
/// Every I/O operation checks permissions before executing.
/// CVE database for npm package vulnerability auditing.
module dun.security;

public import dun.security.permissions;
public import dun.security.cve_db;
