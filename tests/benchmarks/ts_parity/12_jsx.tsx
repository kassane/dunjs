// JSX transformation - classic React.createElement mode.
// Stub React.createElement so the test is self-contained.
type Props = { name: string; count?: number; children?: any };

const React = {
  createElement(type: any, props: Props | null, ...children: any[]): any {
    return { type, props: props || {}, children };
  },
};

function Card({ name, count }: Props) {
  return <div className="card">{name}: {count}</div>;
}

const tree = (
  <ul>
    <li><Card name="alpha" count={1} /></li>
    <li><Card name="beta" count={2} /></li>
    <li>plain text</li>
  </ul>
);

// JSX attribute with spread + bool prop + expression child
const span = <span data-id={42} hidden>{`hi-${5*5}`}</span>;

console.log(tree.type, tree.children.length);
console.log(tree.children[0].children[0].type.name);
console.log(span.type, span.props["data-id"], span.props.hidden, span.children[0]);
