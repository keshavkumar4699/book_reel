/** Ordered, append-only schema migrations (DESIGN.md §7). Never edit a shipped entry. */
export const MIGRATIONS: string[] = [
  `
  create table users (
    id text primary key,
    display_name text not null default 'Reader',
    invite_code text not null unique,
    wpm double precision not null default 230,
    daily_goal_cards int not null default 10,
    freezes_per_week int not null default 1,
    streak jsonb not null default '{"current":0,"best":0,"freezesLeft":1}',
    flagged int not null default 0,
    hidden boolean not null default false,
    created_at timestamptz not null default now()
  );
  -- A signed-in identity (fb:<uid>) that points at an existing device account.
  create table aliases (alias text primary key, user_id text not null references users(id));
  create table reading_days (
    user_id text not null references users(id),
    day date not null,
    verified_cards int not null default 0,
    skimmed_cards int not null default 0,
    minutes double precision not null default 0,
    goal_met boolean not null default false,
    primary key (user_id, day)
  );
  create table reading_events_seen (
    user_id text not null,
    dedupe text not null,
    seen_at timestamptz not null default now(),
    primary key (user_id, dedupe)
  );
  create table follows (
    follower text not null references users(id),
    followee text not null references users(id),
    created_at timestamptz not null default now(),
    primary key (follower, followee)
  );
  create table feed_items (
    id text primary key,
    user_id text not null references users(id),
    type text not null,
    text text not null,
    at timestamptz not null default now()
  );
  create index feed_items_user_at on feed_items (user_id, at desc);
  create table kudos (activity_id text not null references feed_items(id), user_id text not null, primary key (activity_id, user_id));
  create table league_divisions (user_id text primary key references users(id), division int not null default 0);
  create table league_groups (id text primary key, week date not null, division int not null, members int not null default 0);
  create table league_members (
    week date not null,
    user_id text not null references users(id),
    group_id text not null references league_groups(id),
    primary key (week, user_id)
  );
  create table segment_cache (key text primary key, value jsonb not null, created_at timestamptz not null default now());
  create table quota_books (user_id text not null, period text not null, content_hash text not null, primary key (user_id, period, content_hash));
  create table ai_usage (
    id bigserial primary key,
    user_id text not null,
    model text not null,
    input_tokens int not null,
    output_tokens int not null,
    cost_usd double precision not null,
    batch boolean not null,
    at timestamptz not null default now()
  );
  create table batch_jobs (
    id text primary key,
    batch_id text not null,
    user_id text not null,
    content_hash text not null,
    tier text not null,
    card_length text not null,
    reading_level text not null,
    chapters jsonb not null,
    status text not null,
    result jsonb,
    created_at timestamptz not null default now()
  );
  create sequence sync_seq;
  create table sync_items (
    user_id text not null references users(id),
    kind text not null,
    item_id text not null,
    data jsonb,
    updated_at bigint not null,
    deleted boolean not null default false,
    seq bigint not null default nextval('sync_seq'),
    primary key (user_id, kind, item_id)
  );
  create index sync_items_user_seq on sync_items (user_id, seq);
  create table shares (
    id text primary key,
    user_id text not null references users(id),
    type text not null,
    payload jsonb not null,
    open_count int not null default 0,
    created_at timestamptz not null default now()
  )
  `,
  // v-next: an Instagram-style profile (username, pronouns, bio, avatar emoji).
  `
  alter table users add column handle text;
  alter table users add column pronouns text not null default '';
  alter table users add column bio text not null default '';
  alter table users add column avatar text not null default '';
  create unique index users_handle_lower on users (lower(handle)) where handle is not null;
  `,
  // Natural read-aloud: synthesised audio (by text and voice) and daily use.
  `
  create table tts_cache (
    key text primary key,
    content_type text not null,
    audio bytea not null,
    chars int not null,
    created_at timestamptz not null default now()
  );
  create table tts_usage (
    user_id text not null,
    day date not null,
    chars int not null default 0,
    primary key (user_id, day)
  );
  `,
  // Google Play subscriptions, verified with the Play Developer API.
  `
  create table entitlements (
    purchase_token text primary key,
    user_id text,
    product_id text not null,
    tier text not null,
    state text not null,
    expires_at timestamptz,
    test boolean not null default false,
    updated_at timestamptz not null default now()
  );
  create index entitlements_user on entitlements (user_id);
  `,
];
