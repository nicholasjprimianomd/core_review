create table if not exists public.user_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  progress jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_progress enable row level security;

drop policy if exists "Users can read own progress" on public.user_progress;
create policy "Users can read own progress"
on public.user_progress
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert own progress" on public.user_progress;
create policy "Users can insert own progress"
on public.user_progress
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update own progress" on public.user_progress;
create policy "Users can update own progress"
on public.user_progress
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Same shape as user_progress; app + Vercel api/study-progress.js prefer this name first.
create table if not exists public.core_review_study_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  progress jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.core_review_study_progress enable row level security;

drop policy if exists "Users can read own core review progress" on public.core_review_study_progress;
create policy "Users can read own core review progress"
on public.core_review_study_progress
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert own core review progress" on public.core_review_study_progress;
create policy "Users can insert own core review progress"
on public.core_review_study_progress
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update own core review progress" on public.core_review_study_progress;
create policy "Users can update own core review progress"
on public.core_review_study_progress
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Completed exam summaries (per user); synced so history follows the account across devices.
create table if not exists public.core_review_exam_history (
  user_id uuid primary key references auth.users (id) on delete cascade,
  entries jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.core_review_exam_history enable row level security;

drop policy if exists "Users can read own exam history" on public.core_review_exam_history;
create policy "Users can read own exam history"
on public.core_review_exam_history
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert own exam history" on public.core_review_exam_history;
create policy "Users can insert own exam history"
on public.core_review_exam_history
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update own exam history" on public.core_review_exam_history;
create policy "Users can update own exam history"
on public.core_review_exam_history
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
