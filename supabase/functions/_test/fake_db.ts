// Stand-in for the Supabase service-role client: records writes and RPC calls, returns canned rows.

// deno-lint-ignore no-explicit-any
type Row = any;

export function fakeDb(opts: { payment?: Row; refunds?: Row[]; rpcErrors?: Record<string, unknown> } = {}) {
  const rpcCalls: { name: string; args: Row }[] = [];
  const updates: { table: string; values: Row }[] = [];
  const db = {
    from(table: string) {
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: () => q,
        maybeSingle: () => Promise.resolve({ data: table === 'payments' ? opts.payment ?? null : null }),
        // `await query` without maybeSingle(), as the refund lookup does
        // deno-lint-ignore no-explicit-any
        then: (resolve: any) => resolve({ data: table === 'refunds' ? opts.refunds ?? [] : [] }),
        update: (values: Row) => {
          updates.push({ table, values });
          return { eq: () => Promise.resolve({ error: null }) };
        },
      };
      return q;
    },
    rpc(name: string, args: Row) {
      rpcCalls.push({ name, args });
      return Promise.resolve({ error: opts.rpcErrors?.[name] ?? null });
    },
  };
  return { db, rpcCalls, updates };
}
