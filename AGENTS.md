# Agent Rules — JobForum MVP

> **Purpose**: This file is the single source of truth for the AI coding agent  
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
Framework   : Next.js 15
Language    : TypeScript — strict mode ON (no `any`, no `ts-ignore`)
Database    : Supabase (PostgreSQL 15 + RLS + Realtime)
Styling     : Tailwind CSS v4
Components  : shadcn+Tailwind
Auth        : Supabase Auth (Apple + Microsoft for MVP)
Deployment  : Docker
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


## 4. File & Folder Structure

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


### 5.2 Supabase Data Fetching

```ts
// Server component — use server client
import { createServerClient } from '@/lib/supabase/server'

const supabase = await createServerClient()
const { data, error } = await supabase
  .from('posts')
  .select('*, profiles(username), companies(name, slug)')
  .eq('company_id', company.id)
  // NEVER filter by deleted_at here. Fetch all, and let the client render the "已删除" placeholder for soft-deleted items.
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

  const now = new Date().toISOString()

  // 1. Soft delete the post
  const { error } = await supabase
    .from('posts')
    .update({ deleted_at: now, status: 'deleted' })
    .eq('id', postId)
    .eq('user_id', user.id)  // RLS double-check

  if (error) throw new Error(error.message)

  // 2. Cascade soft delete to all comments under this post
  await supabase
    .from('comments')
    .update({ deleted_at: now, status: 'deleted' })
    .eq('post_id', postId)
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

## 7. Auth & Layout Pattern (Zero-Blocking)

- **Root Layout (`app/layout.tsx`)**: NEVER use `supabase.auth.getUser()` or `createClient()` here. The root layout must render immediately. Render `<AppShell isAuthenticated={false | null}>` directly.
- **Client AppShell (`components/features/navigation/app-shell.tsx`)**: Fetch the auth state purely on the client side using `supabase.auth.getSession()`. Update the UI (login/logout buttons) only after the state is resolved. Implement a lightweight "auth pending" state (e.g., hidden buttons or a skeleton) to prevent UI flicker.
- **Route Protection**: Use `middleware.ts` to check for cookie presence as a fast, lightweight guard for protected routes like `/r/[slug]/new`.

---

## 8. Build Order (Fail-Fast Sequence)

**Phase 1: Naked Infrastructure**
Step 1 — Supabase DB: Run schema SQL (Tables & Triggers ONLY. **SKIP all RLS policies**). Seed initial companies.
Step 2 — Lib Setup: Create `lib/types.ts` + `lib/supabase/client.ts` + `lib/supabase/server.ts` (for Server Actions).

**Phase 2: Zero-Blocking Auth & Shell**
Step 3 — Auth Pages: `app/auth/register` + `login` pages.
Step 4 — Global UI: `components/features/navigation/app-shell.tsx` + `nav.tsx` (Fetch session client-side ONLY. Do not block `app/layout.tsx` with server-side auth checks).

**Phase 3: Core Forum (Read & Write)**
Step 5 — Homepage: `app/page.tsx` (List featured companies).
Step 6 — Company Board: `app/r/[slug]/page.tsx` (List posts, no deleted_at filter).
Step 7 — Create Post: `app/r/[slug]/new/page.tsx` + `PostForm` + `createPost` Server Action (Direct insert, no RLS checks).
Step 8 — Post Detail: `app/post/[id]/page.tsx` (Render post body + raw flat comment list).

**Phase 4: Interactions (Tree & Mutations)**
Step 9 — Comment UI: `comment-thread.tsx` (Client-side tree assembly) + `comment-item.tsx`.
Step 10 — Comment Action: `comment-form.tsx` + `createComment` Server Action (Enforce depth guard here).
Step 11 — Soft Deletion: `deletePost` + `deleteComment` Server Actions (Direct update, cascade soft-delete).

**Phase 5: User Identity**
Step 12 — Profile: `app/u/[username]/page.tsx` (Display user info and their public posts).

**Do not skip steps. Do not build step N+1 until step N is working.**

---

## 9. Environment Variables

```bash
# .env.local
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGci...
```

Never commit `.env.local`. Never use `SUPABASE_SERVICE_ROLE_KEY` in client code.

*Last updated: MVP phase — posts, comments, replies only.*


## 8. UI Rules

- Do not edit `components/ui/*` directly; wrap in `components/features/*`.
- Use Tailwind utilities only; no custom CSS files.
- Any account picker must display a human-readable account label in the trigger and menu.
- Never show raw account IDs in user-facing selects, summaries, or transaction metadata when an account name is available.
- Navigation loading must use existing Next.js route loading and the existing `PendingLinkVeil` pattern on `Link` navigations.
- Do not add global loading via `fetch` interception, `window.fetch` monkeypatching, or other request-level overlays.
- Submit flows should keep loading local to the triggering control or dialog; do not stack a global page overlay on top of form submission pending states.

## 9. Development Hygiene

- Typecheck: `npx tsc --noEmit`
- Tests: `npm test`

## 10. Cloudflare + One-File Env + All-in-One Docker Image (English)

- Security is not a concern for this deployment mode (secrets may be baked into the image).
- Use a single env file at repo root:
  - `.env.local` for local dev.
  - Copy `.env.local` to `.env` for build/runtime. Do not use other env files.
  - Include both public and private vars in that single file (e.g., `NEXT_PUBLIC_SUPABASE_ANON_KEY`, service role keys, OAuth secrets).
- Dockerfile rules:
  - Copy the `.env` into both build and runtime stages. No `--build-arg` or `--env-file` flags are needed.
  - Build command: `docker build -t next-app:latest .` (no extra args).
  - Runtime: `docker run -d --name folio-frontend -p 80:80 -p 443:443 --restart always next-app:latest`.
- Cloudflare setup:
  - Host the domain on Cloudflare, enable the orange-cloud proxy.
  - Set SSL mode to “Full (strict)”.
  - Certbot on the host is not required because the Cloudflare Origin Certificate is baked into the image.
- All-in-One image:
  - The image should bundle Nginx and the app in a single container.
  - Port 80 redirects to HTTPS; port 443 terminates TLS with the baked-in Cloudflare Origin Certificate.
  - Nginx config inside the image must include:
    - `client_header_buffer_size 32k;`
    - `large_client_header_buffers 8 64k;`
  - Expose/serve both port 80 and 443 inside the container.

## 11. No-Nonsense / Fail-Fast Developer Prompt

- **Role:** Act as a Senior Software Architect specializing in Clean Code and the Fail-Fast principle.
- **Core Instruction:** Optimize code by stripping away all "defensive programming" garbage. Do not provide "safety nets" that swallow errors or waste tokens.
- **Strict Requirements:**
  - **No Silent Failures:** Never use empty catch blocks or return vague values like null, undefined, or {} just to prevent a crash. If something is wrong, let it throw an error.
  - **Eliminate "Garbage" Logic:** Remove redundant null checks or `if (data)` wrappers if the logic logically requires that data to exist. Expose exactly where the chain breaks.
  - **Precision over Robustness:** Prefer a "brittle" but honest script over a "robust" but lying one. The code should be a "surgical strike"—minimalist, readable, and direct.
  - **Expose the Root Cause:** If an API call fails or a configuration is missing, the error must be loud and clear in the console immediately.
- **Goal:** Transform "defensive/messy" code into a "naked/high-performance" implementation. If you see a potential issue, report it as a bug rather than coding around it.
- **Server Action Boundaries:** While logic must fail fast, Server Actions must catch these immediate errors at the top level and return them safely to the client (e.g., `return { error: error.message }`). The client UI MUST display this error loudly via a Toast or Alert component. Do not let unhandled promise rejections crash the Next.js router.
