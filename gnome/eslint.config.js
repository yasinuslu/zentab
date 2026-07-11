// @ts-check
import js from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      // GJS is neither Node nor a browser: no `require`, no `window`, no `process`. The
      // handful of true globals (log, imports, ARGV, globalThis, print...) are covered by
      // `globals.gjs`; `global` (the Shell singleton) and `_` (gettext) are added below.
      globals: {
        ...globals.gjs,
        global: "readonly",
        _: "readonly",
        ngettext: "readonly",
      },
    },
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      // GObject.registerClass classes and GJS signal handlers routinely need `this` typed
      // loosely and non-null assertions on lazily-initialized fields set up in enable().
      "@typescript-eslint/no-non-null-assertion": "off",
      "no-console": "off",
    },
  },
  {
    ignores: ["dist/**", "node_modules/**"],
  },
);
