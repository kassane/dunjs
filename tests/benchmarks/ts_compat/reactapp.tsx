// react-app.tsx — JSX/TSX: React classic-mode emit, fragments, spreads,
// member tags, nested components, hooks-style patterns

// DunJS installs a tiny React shim on globalThis for JSX classic mode:
//   React.createElement(type, props, ...children)
//   React.Fragment

// ── Types ─────────────────────────────────────────────────────────────────
interface Props {
  className?: string;
  children?: any;
  style?: Record<string, string | number>;
}

interface ButtonProps extends Props {
  onClick?: () => void;
  disabled?: boolean;
  variant?: "primary" | "secondary" | "danger";
}

interface CardProps extends Props {
  title: string;
  subtitle?: string;
  footer?: any;
}

interface ListProps<T> {
  items: T[];
  renderItem: (item: T, index: number) => any;
  keyExtractor: (item: T) => string;
  emptyMessage?: string;
}

// ── Simple functional component ───────────────────────────────────────────
function Button({ onClick, disabled = false, variant = "primary", children }: ButtonProps) {
  const variantClass = `btn-${variant}`;
  return (
    <button
      className={`btn ${variantClass}`}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  );
}

// ── Component using Fragment ───────────────────────────────────────────────
function Card({ title, subtitle, children, footer }: CardProps) {
  return (
    <div className="card">
      <div className="card-header">
        <>
          <h2>{title}</h2>
          {subtitle && <p className="subtitle">{subtitle}</p>}
        </>
      </div>
      <div className="card-body">{children}</div>
      {footer && <div className="card-footer">{footer}</div>}
    </div>
  );
}

// ── Generic list component ────────────────────────────────────────────────
function List<T>({ items, renderItem, keyExtractor, emptyMessage = "No items" }: ListProps<T>) {
  if (items.length === 0) {
    return <div className="empty">{emptyMessage}</div>;
  }
  return (
    <ul>
      {items.map((item, index) => (
        <li key={keyExtractor(item)}>{renderItem(item, index)}</li>
      ))}
    </ul>
  );
}

// ── Namespace-style component (member tag) ────────────────────────────────
namespace Form {
  export function Root({ children }: Props) {
    return <form className="form">{children}</form>;
  }
  export function Field({ children, className }: Props) {
    return <div className={`field ${className ?? ""}`}>{children}</div>;
  }
  export function Label({ children }: Props) {
    return <label>{children}</label>;
  }
  export function Input({ ...props }: any) {
    return <input {...props} />;
  }
  export function Submit({ children }: Props) {
    return <button type="submit">{children}</button>;
  }
}

// ── Spread props ──────────────────────────────────────────────────────────
function Input({ className, ...rest }: any) {
  return <input className={`input ${className ?? ""}`} {...rest} />;
}

// ── Conditional rendering ─────────────────────────────────────────────────
function Alert({ type, message }: { type: "info" | "warning" | "error"; message: string }) {
  const icons = { info: "ℹ️", warning: "⚠️", error: "❌" };
  return (
    <div className={`alert alert-${type}`}>
      <span>{icons[type]}</span>
      <span>{message}</span>
    </div>
  );
}

// ── Composition ───────────────────────────────────────────────────────────
interface User {
  id: string;
  name: string;
  email: string;
  role: "admin" | "user" | "guest";
}

function UserRow({ user }: { user: User }) {
  return (
    <tr>
      <td>{user.id}</td>
      <td>{user.name}</td>
      <td>{user.email}</td>
      <td>
        <span className={`badge badge-${user.role}`}>{user.role}</span>
      </td>
    </tr>
  );
}

function UserTable({ users }: { users: User[] }) {
  return (
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Name</th>
          <th>Email</th>
          <th>Role</th>
        </tr>
      </thead>
      <tbody>
        {users.map((u) => (
          <UserRow key={u.id} user={u} />
        ))}
      </tbody>
    </table>
  );
}

// ── App root ──────────────────────────────────────────────────────────────
function App() {
  const users: User[] = [
    { id: "1", name: "Alice", email: "alice@example.com", role: "admin" },
    { id: "2", name: "Bob", email: "bob@example.com", role: "user" },
    { id: "3", name: "Charlie", email: "charlie@example.com", role: "guest" },
  ];

  const todos = ["Buy groceries", "Write tests", "Deploy to prod"];

  return (
    <>
      <Alert type="info" message="DunJS JSX/TSX support working!" />

      <Card title="User Management" subtitle="Manage system users" footer={<Button variant="primary">Add User</Button>}>
        <UserTable users={users} />
      </Card>

      <Card title="Todo List">
        <List
          items={todos}
          keyExtractor={(item) => item}
          renderItem={(item, i) => <span>{i + 1}. {item}</span>}
          emptyMessage="No todos!"
        />
      </Card>

      <Form.Root>
        <Form.Field>
          <Form.Label>Username</Form.Label>
          <Form.Input type="text" placeholder="Enter username" required />
        </Form.Field>
        <Form.Field>
          <Form.Label>Password</Form.Label>
          <Form.Input type="password" placeholder="Enter password" />
        </Form.Field>
        <Form.Submit>Login</Form.Submit>
      </Form.Root>

      <div>
        <Button variant="primary" onClick={() => console.log("primary clicked")}>Primary</Button>
        <Button variant="secondary">Secondary</Button>
        <Button variant="danger" disabled>Danger (disabled)</Button>
      </div>

      <Input className="search" type="search" placeholder="Search..." />
    </>
  );
}

// ── Render (virtual DOM walk) ─────────────────────────────────────────────
function renderToString(node: any, depth = 0): string {
  if (node === null || node === undefined || node === false) return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map((n) => renderToString(n, depth)).join("");

  const { type, props } = node;
  const { children, key, ...attrs } = props ?? {};

  const tagName = typeof type === "string" ? type : type?.name ?? "unknown";

  // Functional component — call it
  if (typeof type === "function") {
    const result = type(props);
    return renderToString(result, depth);
  }

  const attrStr = Object.entries(attrs)
    .filter(([k, v]) => v !== undefined && v !== false && k !== "onClick" && k !== "onChange")
    .map(([k, v]) => `${k}="${v}"`)
    .join(" ");

  const selfClose = ["input", "br", "hr", "img", "meta", "link"].includes(tagName);
  const inner = Array.isArray(children)
    ? children.map((c: any) => renderToString(c, depth + 1)).join("")
    : renderToString(children, depth + 1);

  if (selfClose) return `<${tagName}${attrStr ? " " + attrStr : ""} />`;
  return `<${tagName}${attrStr ? " " + attrStr : ""}>${inner}</${tagName}>`;
}

// ── Run ───────────────────────────────────────────────────────────────────
console.log("=== JSX/TSX Render Test ===");

// Test individual components
const btn = <Button variant="primary">Click Me</Button>;
console.log("Button type:", typeof btn);
console.log("Button type.name:", btn.type?.name ?? btn.type);
console.log("Button props.variant:", btn.props?.variant);
console.log("Button children:", btn.props?.children);

const card = <Card title="Test Card" subtitle="A subtitle">Content here</Card>;
console.log("Card type:", card.type?.name ?? card.type);
console.log("Card title:", card.props?.title);

// Render App
const app = <App />;
const html = renderToString(app);
console.log("\n=== Rendered HTML (excerpt) ===");
console.log(html.slice(0, 300) + (html.length > 300 ? "..." : ""));
console.log("\nTotal rendered length:", html.length);

// Verify key structures
console.log("\n=== Assertions ===");
console.log("Has <table>:", html.includes("<table>"));
console.log("Has Alice:", html.includes("Alice"));
console.log("Has admin badge:", html.includes("badge-admin"));
console.log("Has form:", html.includes("<form"));
console.log("Has login button:", html.includes("Login"));
console.log("Has search input:", html.includes('type="search"'));
console.log("Has todo items:", html.includes("Buy groceries"));

console.log("\nJSX/TSX all OK");
