# Agent Rules — JobForum MVP

> **Purpose**: This file is the single source of truth for the AI coding agent (Cursor).  
> Read this entire file before writing any code. Follow every rule exactly.

---

## 0. Project Identity

| Field | Value |
|---|---|
| **Product** | Reddit-style company review & discussion forum for Mainland China job seekers |
| **Routes** | `/r/[company_slug]` (company boards) · `/u/[username]` (user profiles) · `/post/[id]` (thread view) |
| **Phase** | **MVP** — text-only, no image uploads, no edit post |
| **Iteration style** | Fail-fast. Ship the smallest working slice, then extend. |

---

## 1. Technology Stack (Locked)

```
Framework   : Next.js 15 (App Router, React 19)
Language    : TypeScript — strict mode ON (no `any`, no `ts-ignore`)
Database    : Supabase (PostgreSQL 15 + RLS + Realtime)
Styling     : Tailwind CSS v4
Components  : shadcn/ui (radix primitives)
Auth        : Supabase Auth (email+password for MVP)
Deployment  : Vercel (free tier)
```

**Never introduce new dependencies without asking first.**

---

## 2. MVP Scope

### ✅ IN scope (build this now)

- User registration & login (Supabase Auth)
- Browse company boards `/r/[slug]`
- Create a post inside a company board
- Delete own post (soft-delete)
- Write a top-level comment on a post
- Reply to a comment (max depth = 2, i.e. comment → reply only)
- Delete own comment (soft-delete, show "已删除" placeholder)
- View user profile `/u/[username]` showing their public posts

### ❌ OUT of scope for MVP (do not build)

- Edit post / edit comment
- Upvote / downvote
- Direct messaging / friends
- Search
- Notifications
- AI moderation bot
- Image uploads
- Company creation by users (seed companies via SQL only)

---

## 3. Database Schema

### 3.1 Run this SQL in Supabase SQL Editor (in order)

```sql
-- =========================================================
-- EXTENSIONS
-- =========================================================
create extension if not exists "pgcrypto";

-- =========================================================
-- TABLE: profiles
-- Extends Supabase auth.users 1-to-1
-- =========================================================
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text not null unique,
  bio           text,
  user_type     text not null default 'human' check (user_type in ('human', 'bot', 'admin')),
  status        text not null default 'active' check (status in ('active', 'suspended', 'deleted')),
  created_at    timestamptz not null default now()
);

-- Auto-create profile row on new auth signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =========================================================
-- TABLE: companies
-- Seeded by admin/migration; users cannot create in MVP
-- =========================================================
create table public.companies (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text not null unique,                   -- used in /r/[slug]
  aliases       text[] default '{}',                   -- alternate names for search
  description   text,
  logo_url      text,
  post_count    int not null default 0,
  created_at    timestamptz not null default now()
);

create index on public.companies (slug);
create index on public.companies using gin (aliases);  -- fuzzy search later

-- =========================================================
-- TABLE: posts
-- Top-level threads inside a company board
-- =========================================================
create table public.posts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  company_id    uuid not null references public.companies(id) on delete cascade,
  title         text not null check (char_length(title) between 2 and 200),
  body          text not null check (char_length(body) between 1 and 20000),
  post_type     text not null default 'discussion'
                  check (post_type in ('discussion', 'interview', 'salary', 'review')),
  status        text not null default 'published'
                  check (status in ('published', 'pending', 'rejected', 'deleted')),
  comment_count int not null default 0,
  is_pinned     boolean not null default false,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz                             -- soft delete
);

create index on public.posts (company_id, created_at desc);
create index on public.posts (user_id, created_at desc);
create index on public.posts (status, created_at desc);

-- =========================================================
-- TABLE: comments
-- Both top-level comments AND nested replies via parent_id
-- =========================================================
create table public.comments (
  id            uuid primary key default gen_random_uuid(),
  post_id       uuid not null references public.posts(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  parent_id     uuid references public.comments(id) on delete cascade,  -- NULL = top-level
  body          text not null check (char_length(body) between 1 and 5000),
  depth         smallint not null default 0 check (depth between 0 and 2), -- 0 = top, 1 = reply
  status        text not null default 'published'
                  check (status in ('published', 'pending', 'rejected', 'deleted')),
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index on public.comments (post_id, created_at asc);
create index on public.comments (parent_id);
create index on public.comments (user_id);

-- =========================================================
-- TRIGGERS: keep comment_count in sync
-- =========================================================
create or replace function public.update_post_comment_count()
returns trigger language plpgsql security definer as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts set comment_count = comment_count + 1 where id = NEW.post_id;
  elsif TG_OP = 'UPDATE' and NEW.deleted_at is not null and OLD.deleted_at is null then
    update public.posts set comment_count = greatest(comment_count - 1, 0) where id = NEW.post_id;
  end if;
  return null;
end;
$$;

create trigger sync_comment_count
  after insert or update on public.comments
  for each row execute procedure public.update_post_comment_count();
```

### 3.2 RLS Policies

```sql
-- =========================================================
-- Enable RLS on all tables
-- =========================================================
alter table public.profiles  enable row level security;
alter table public.companies enable row level security;
alter table public.posts     enable row level security;
alter table public.comments  enable row level security;

-- =========================================================
-- profiles
-- =========================================================
-- Anyone can read profiles
create policy "profiles: public read"
  on public.profiles for select using (true);

-- Users can update only their own profile
create policy "profiles: owner update"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- =========================================================
-- companies
-- =========================================================
-- Anyone can read companies (including guests)
create policy "companies: public read"
  on public.companies for select using (true);

-- Only service_role / admin can insert (seeding only)
-- No insert policy for anon/authenticated in MVP

-- =========================================================
-- posts
-- =========================================================
-- Published, non-deleted posts are public
create policy "posts: public read"
  on public.posts for select
  using (status = 'published' and deleted_at is null);

-- Authenticated users can insert
create policy "posts: authenticated insert"
  on public.posts for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Owner can soft-delete (set deleted_at, status='deleted')
create policy "posts: owner soft delete"
  on public.posts for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and deleted_at is not null   -- only allow setting deleted_at
    and status = 'deleted'
  );

-- =========================================================
-- comments
-- =========================================================
create policy "comments: public read"
  on public.comments for select
  using (deleted_at is null);

create policy "comments: authenticated insert"
  on public.comments for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "comments: owner soft delete"
  on public.comments for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and deleted_at is not null
    and status = 'deleted'
  );
```

### 3.3 Seed Data (run after schema)

```sql
-- Sample companies (add more as needed)
insert into public.companies (name, slug, aliases, description) values
  ('字节跳动', 'bytedance',    array['ByteDance','字节','抖音集团'],    '互联网科技公司，旗下产品包括抖音、TikTok、今日头条。'),
  ('阿里巴巴', 'alibaba',      array['Alibaba','阿里','淘宝','天猫'],   '电商及云计算巨头。'),
  ('腾讯',     'tencent',      array['Tencent','TX','微信'],            '游戏、社交、金融科技综合集团。'),
  ('美团',     'meituan',      array['Meituan','美团点评'],             '生活服务平台。'),
  ('京东',     'jd',           array['JD','京东商城'],                  '电商及物流。'),
  ('华为',     'huawei',       array['Huawei'],                         '通信设备、手机、云计算。');
```

---

## 4. File & Folder Structure

```
.
├── .cursor/
│   └── rules/
│       └── agent.md          ← this file
│
├── app/
│   ├── layout.tsx             ← root layout (Providers, fonts)
│   ├── page.tsx               ← homepage (list featured companies)
│   │
│   ├── r/
│   │   └── [slug]/
│   │       ├── page.tsx       ← company board (list posts)
│   │       └── new/
│   │           └── page.tsx   ← create post form
│   │
│   ├── post/
│   │   └── [id]/
│   │       └── page.tsx       ← post thread + comments
│   │
│   ├── u/
│   │   └── [username]/
│   │       └── page.tsx       ← user profile
│   │
│   └── auth/
│       ├── login/page.tsx
│       └── register/page.tsx
│
├── components/
│   ├── ui/                    ← shadcn/ui auto-generated (do not edit)
│   ├── post-card.tsx          ← post preview (used in board + profile)
│   ├── post-form.tsx          ← create post form (client component)
│   ├── comment-thread.tsx     ← recursive comment list
│   ├── comment-item.tsx       ← single comment row
│   ├── comment-form.tsx       ← reply / new comment box (client)
│   ├── company-header.tsx     ← company board header
│   └── nav.tsx                ← top navigation bar
│
├── lib/
│   ├── supabase/
│   │   ├── client.ts          ← browser client (createBrowserClient)
│   │   ├── server.ts          ← server client (createServerClient + cookies)
│   │   └── middleware.ts      ← refresh session middleware
│   └── types.ts               ← all DB row types (generated or manual)
│
├── middleware.ts               ← Next.js middleware (session refresh)
└── .env.local                  ← NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY
```

---

## 5. Coding Conventions

### 5.1 Server vs. Client Components

```
DEFAULT = Server Component (no 'use client')
Add 'use client' ONLY when you need:
  - useState / useEffect / useReducer
  - onClick / onChange event handlers
  - Browser APIs
  - shadcn/ui form components (they use Radix which needs interactivity)
```

**Pattern**: fetch data in Server Component, pass to a thin Client Component for interaction.

```tsx
// ✅ GOOD — server fetches, client renders form
// app/r/[slug]/new/page.tsx  (Server Component)
export default async function NewPostPage({ params }) {
  const company = await getCompany(params.slug)   // server-side fetch
  return <PostForm company={company} />            // client component
}

// ❌ BAD — fetching in client with useEffect
```

### 5.2 Supabase Data Fetching

```ts
// Server component — use server client
import { createServerClient } from '@/lib/supabase/server'

const supabase = await createServerClient()
const { data, error } = await supabase
  .from('posts')
  .select('*, profiles(username), companies(name, slug)')
  .eq('company_id', company.id)
  .eq('status', 'published')
  .is('deleted_at', null)
  .order('created_at', { ascending: false })
  .limit(30)

// Always handle error
if (error) throw new Error(error.message)
```

### 5.3 Mutations — Use Server Actions

```ts
// lib/actions/posts.ts
'use server'
import { createServerClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function createPost(formData: FormData) {
  const supabase = await createServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { error } = await supabase.from('posts').insert({
    user_id: user.id,
    company_id: formData.get('company_id') as string,
    title:      formData.get('title') as string,
    body:       formData.get('body') as string,
    post_type:  formData.get('post_type') as string,
  })

  if (error) throw new Error(error.message)
  revalidatePath(`/r/${formData.get('slug')}`)
}
```

### 5.4 Soft Delete Pattern

```ts
// NEVER use .delete() — always soft delete
export async function deletePost(postId: string) {
  const supabase = await createServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  await supabase
    .from('posts')
    .update({ deleted_at: new Date().toISOString(), status: 'deleted' })
    .eq('id', postId)
    .eq('user_id', user.id)  // RLS double-check
}
```

### 5.5 Comment Depth Guard

```ts
// Before inserting a reply, always check parent depth
export async function createComment(postId: string, body: string, parentId?: string) {
  const supabase = await createServerClient()

  let depth = 0
  if (parentId) {
    const { data: parent } = await supabase
      .from('comments')
      .select('depth')
      .eq('id', parentId)
      .single()

    if (!parent) throw new Error('Parent comment not found')
    if (parent.depth >= 1) throw new Error('最多只能嵌套两层回复')
    depth = parent.depth + 1
  }

  await supabase.from('comments').insert({
    post_id: postId,
    user_id: (await supabase.auth.getUser()).data.user!.id,
    parent_id: parentId ?? null,
    body,
    depth,
  })
}
```

### 5.6 TypeScript Types

```ts
// lib/types.ts — derive from Supabase generated types or define manually
export type Profile = {
  id: string
  username: string
  bio: string | null
  user_type: 'human' | 'bot' | 'admin'
  status: 'active' | 'suspended' | 'deleted'
  created_at: string
}

export type Post = {
  id: string
  user_id: string
  company_id: string
  title: string
  body: string
  post_type: 'discussion' | 'interview' | 'salary' | 'review'
  status: 'published' | 'pending' | 'rejected' | 'deleted'
  comment_count: number
  is_pinned: boolean
  created_at: string
  deleted_at: string | null
  // joined
  profiles?: Pick<Profile, 'username'>
  companies?: Pick<Company, 'name' | 'slug'>
}

export type Comment = {
  id: string
  post_id: string
  user_id: string
  parent_id: string | null
  body: string
  depth: number
  status: 'published' | 'pending' | 'rejected' | 'deleted'
  created_at: string
  deleted_at: string | null
  profiles?: Pick<Profile, 'username'>
  replies?: Comment[]   // client-assembled, not from DB
}

export type Company = {
  id: string
  name: string
  slug: string
  aliases: string[]
  description: string | null
  post_count: number
  created_at: string
}
```

---

## 6. Component Patterns

### Post card (server-renderable)

```tsx
// components/post-card.tsx
import Link from 'next/link'
import { Post } from '@/lib/types'
import { formatDistanceToNow } from 'date-fns/formatDistanceToNow'
import { zhCN } from 'date-fns/locale'

export function PostCard({ post }: { post: Post }) {
  return (
    <article className="border-b py-4 px-2 hover:bg-muted/40 transition-colors">
      <div className="flex items-center gap-2 text-xs text-muted-foreground mb-1">
        <span>{post.profiles?.username ?? '匿名'}</span>
        <span>·</span>
        <span>{formatDistanceToNow(new Date(post.created_at), { locale: zhCN, addSuffix: true })}</span>
        <span className="ml-auto">{post.comment_count} 条回复</span>
      </div>
      <Link href={`/post/${post.id}`} className="block">
        <h2 className="text-base font-medium leading-snug">{post.title}</h2>
        <p className="text-sm text-muted-foreground mt-1 line-clamp-2">{post.body}</p>
      </Link>
    </article>
  )
}
```

### Comment thread (client component for interactivity)

```tsx
// components/comment-thread.tsx
'use client'
// - Receives flat list of comments from server
// - Assembles tree client-side by parent_id
// - Renders <CommentItem> recursively up to depth 2
// - Shows <CommentForm> for reply at each level
```

---

## 7. Auth Guard Pattern

```tsx
// Protect pages that require login
// app/r/[slug]/new/page.tsx
import { redirect } from 'next/navigation'
import { createServerClient } from '@/lib/supabase/server'

export default async function NewPostPage() {
  const supabase = await createServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')
  // ...
}
```

---

## 8. Build Order (follow this sequence)

```
Step 1  — Supabase: run schema SQL + RLS + seed companies
Step 2  — lib/supabase/client.ts + server.ts + middleware.ts
Step 3  — lib/types.ts
Step 4  — middleware.ts (session refresh)
Step 5  — app/auth/register + login pages
Step 6  — components/nav.tsx (login state awareness)
Step 7  — app/page.tsx (company list homepage)
Step 8  — app/r/[slug]/page.tsx (company board — list posts)
Step 9  — app/r/[slug]/new/page.tsx + PostForm + createPost action
Step 10 — app/post/[id]/page.tsx (post detail + flat comment list)
Step 11 — components/comment-thread.tsx + comment-item.tsx (tree assembly)
Step 12 — components/comment-form.tsx + createComment action (with depth guard)
Step 13 — Delete post / delete comment actions
Step 14 — app/u/[username]/page.tsx (profile + public posts)
```

**Do not skip steps. Do not build step N+1 until step N is working.**

---

## 9. Environment Variables

```bash
# .env.local
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGci...
```

Never commit `.env.local`. Never use `SUPABASE_SERVICE_ROLE_KEY` in client code.

---

## 10. Do-Nots (hard rules for this codebase)

| ❌ Never do | ✅ Do instead |
|---|---|
| `any` type | Proper type from `lib/types.ts` |
| Physical `.delete()` on posts/comments | Soft delete via `deleted_at` |
| `useEffect` for data fetching | Server Component fetch |
| Inline SQL strings outside `lib/` | Keep all DB calls in `lib/actions/` or server components |
| Expose service role key to client | Use anon key only on client |
| Comment nesting beyond depth 1 | Check and throw before insert |
| Edit post/comment (MVP is out) | Return 405 or just don't build it |

---

*Last updated: MVP phase — posts, comments, replies only.*
