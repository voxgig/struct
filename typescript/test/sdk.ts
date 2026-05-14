import { StructUtility } from '../dist/StructUtility'

class SDK {
  #opts: any = {}
  #utility: any = {}

  constructor(opts?: any) {
    this.#opts = opts || {}
    this.#utility = {
      struct: new StructUtility(),
      contextify: (ctxmap: any) => ctxmap,
      makeContext: (ctxmap: any) => ctxmap,
      check: (ctx: any) => {
        return {
          zed:
            'ZED' +
            (null == this.#opts ? '' : null == this.#opts.foo ? '' : this.#opts.foo) +
            '_' +
            (null == ctx.meta?.bar ? '0' : ctx.meta.bar),
        }
      },
    }
  }

  static async test(opts?: any) {
    return new SDK(opts)
  }

  async tester(opts?: any) {
    return new SDK(opts || this.#opts)
  }

  utility() {
    return this.#utility
  }
}

export { SDK }
