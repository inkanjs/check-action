// A breaking pull request: the 200 answer no longer sends price.
import { inkan, problem, t } from "@vxnsin/inkan";

export const app = inkan({ title: "Fixture", version: "1.0.0" });

const Tea = t.object({ id: t.int(), name: t.string() }).named("Tea");
const teas = [{ id: 1, name: "Sencha" }];

app.get(
  "/teas/:id",
  {
    summary: "One tea",
    params: t.object({ id: t.int() }),
    response: { 200: Tea, 404: t.problem() },
    examples: [
      { name: "sencha", params: { id: 1 }, expect: { name: "Sencha" } },
      { name: "none", params: { id: 9 }, status: 404 },
    ],
  },
  ({ params }) => {
    const tea = teas.find((x) => x.id === params.id);
    if (!tea) throw problem(404, "no-tea", "There is no such tea");
    return tea;
  },
);

app.listen();
