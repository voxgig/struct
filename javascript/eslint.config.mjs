// Flat ESLint config for the JavaScript port.

import js from '@eslint/js'
import globals from 'globals'

export default [
  {
    ignores: ['node_modules/', 'coverage/'],
  },
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'commonjs',
      globals: { ...globals.node },
    },
    rules: {
      // The source is ported verbatim across every language; the
      // init-then-reassign patterns that ESLint 10's `no-useless-assignment`
      // flags are kept on purpose to preserve line-for-line structural parity.
      'no-useless-assignment': 'off',
      'no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],
    },
  },
]
