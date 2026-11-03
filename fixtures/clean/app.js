// A clean pull request: a new optional field in the answer and a new route.
import { inkan, problem, t } from "@vxnsin/inkan";

export const app = inkan({ title: "Fixture", version: "1.0.0" });

const Tea = t.object({ id: t.int(), name: t.string(), price: t.number(), origin: t.string().optional() }).named("Tea");
const teas = [{ id: 1, name: "Sencha", price: 9.5 }];

app.get(
  "/teas/:id",
  {
    summary: "One tea",
    params: t.object({ id: t.int() }),
    response: { 200: Tea, 404: t.problem() },
    examples: [
      { name: "sencha", params: { id: 1 }, expect: { name: "Sencha", price: 9.5 } },
      { name: "none", params: { id: 9 }, status: 404 },
    ],
  },
  ({ params }) => {
    const tea = teas.find((x) => x.id === params.id);
    if (!tea) throw problem(404, "no-tea", "There is no such tea");
    return tea;
  },
);

app.get(
  "/teas",
  {
    summary: "All teas",
    response: { 200: t.array(Tea) },
    examples: [{ name: "the shelf", expect: [{ name: "Sencha" }] }],
  },
  () => teas,
);

app.listen();
