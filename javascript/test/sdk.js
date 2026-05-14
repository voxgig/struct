const { StructUtility } = require('../src/struct')

class SDK {
  #opts = {}
  #utility = {}

  constructor(opts) {
    this.#opts = opts || {}
    this.#utility = {
      struct: new StructUtility(),
      contextify: (ctxmap) => ctxmap,
      check: (ctx) => {
        return {
          zed:
            'ZED' +
            (null == this.#opts ? '' : null == this.#opts.foo ? '' : this.#opts.foo) +
            '_' +
            (null == ctx.meta.bar ? '0' : ctx.meta.bar),
        }
      },
    }
  }

  static async test(opts) {
    return new SDK(opts)
  }

  async tester(opts) {
    return new SDK(opts || this.#opts)
  }

  utility() {
    return this.#utility
  }
}

module.exports = {
  SDK,
}
