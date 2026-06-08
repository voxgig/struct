// Flat ESLint config for the canonical TypeScript port.
// See https://typescript-eslint.io/getting-started/

import js from '@eslint/js'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  {
    ignores: ['dist/', 'dist-test/', 'node_modules/', 'coverage/', 'test/quick.js'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.node },
    },
    rules: {
      // The library is deliberately "JSON-shaped any" at its boundaries.
      '@typescript-eslint/no-explicit-any': 'off',
      // The source is ported verbatim across every language; the
      // init-then-reassign patterns that ESLint 10's `no-useless-assignment`
      // flags are kept on purpose to preserve line-for-line structural parity.
      'no-useless-assignment': 'off',
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
    },
  },
)
