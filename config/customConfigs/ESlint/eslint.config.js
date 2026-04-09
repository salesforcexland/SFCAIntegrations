export default [
  {
    files: ["**/*.js"],

    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
    },

    rules: {
      // Easy-to-trigger rules for testing
      "no-unused-vars": "error",
      "no-console": "error",
      "no-alert": "error",
      "eqeqeq": ["error", "always"],
      "no-debugger": "error",

      // Style-ish (just to see variety)
      "semi": ["error", "always"],
      "quotes": ["error", "single"],

      // Slightly more interesting
      "no-constant-condition": "warn",
    },
  },
];