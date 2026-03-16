insert into storage.buckets (id, name, public)
values ('core-review-content', 'core-review-content', true)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "Public can read Core Review content" on storage.objects;
create policy "Public can read Core Review content"
on storage.objects
for select
to public
using (bucket_id = 'core-review-content');

drop policy if exists "Service role manages Core Review content" on storage.objects;
create policy "Service role manages Core Review content"
on storage.objects
for all
to service_role
using (bucket_id = 'core-review-content')
with check (bucket_id = 'core-review-content');
