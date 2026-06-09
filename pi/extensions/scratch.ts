import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "greet",
    label: "Greet",
    description: "Greet someone by name.",          // the model reads this to decide WHEN to call
    parameters: Type.Object({                        // the ABI: what the model must supply
      name: Type.String({ description: "Name to greet" }),
    }),
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      return {
        content: [{ type: "text", text: `Hello, ${params.name}!` }], // what re-enters the model's context
        details: { greeted: params.name },                            // structured side-channel (UI/state)
      };
    },
  });
}
