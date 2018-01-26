begin;

drop schema if exists pomb, pomb_private cascade;
drop role if exists pomb_admin, pomb_anonymous, pomb_account;

create schema pomb;
create schema pomb_private;

alter default privileges revoke execute on functions from public;

create table pomb.account (
  id                  serial primary key,
  username            text unique not null check (char_length(username) < 80),
  first_name          text check (char_length(first_name) < 80),
  last_name           text check (char_length(last_name) < 100),
  profile_photo       text,
  hero_photo          text,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

insert into pomb.account (username, first_name, last_name, profile_photo) values
  ('teeth-creep', 'Ms', 'D', 'https://laze-app.s3.amazonaws.com/19243203_10154776689779211_34706076750698170_o-w250-1509052127322.jpg');

comment on table pomb.account is 'Table with POMB users';
comment on column pomb.account.id is 'Primary id for account';
comment on column pomb.account.username is 'username of account';
comment on column pomb.account.first_name is 'First name of account';
comment on column pomb.account.last_name is 'Last name of account';
comment on column pomb.account.profile_photo is 'Profile photo of account';
comment on column pomb.account.hero_photo is 'Hero photo of account';
comment on column pomb.account.created_at is 'When account created';
comment on column pomb.account.updated_at is 'When account last updated';

--alter table pomb.account enable row level security;

-- Limiting choices for category field on post
create type pomb.post_category as enum (
  'Trekking',
  'Biking',
  'Travel',
  'Culture',
  'Gear',
  'Food'
);

create table pomb.post (
  id                  serial primary key,
  author              integer not null references pomb.account(id) on delete cascade,
  title               text not null check (char_length(title) < 200),
  subtitle            text not null check (char_length(title) < 300),
  content             text not null,
  category            pomb.post_category,
  is_draft            boolean not null,
  is_scheduled        boolean not null,
  scheduled_date      bigint,
  is_published        boolean not null,
  published_date      bigint,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

insert into pomb.post (author, title, subtitle, content, category, is_draft, is_scheduled, scheduled_date, is_published, published_date) values
  (1, 'Explore The World', 'Neat Info', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Trekking', false, false, null, true, 1495726380000),
  (1, 'Lose Your Way? Find a Beer', 'No Bud Light though', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Biking', false, false, null, true, 1295726380000),
  (1, 'Sports through the lense of global culture', 'Its not all football out there', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Culture', true, false, null, false, null),
  (1, 'Riding the Silk Road', 'Bets way to see central asia. You will love it for sure. Going to see so much stuff. Should be great. Follow along as some dipshit does some stuff out in the desert and he is like. Whoa. Hot dog what a story we are going to have to share.Should be great', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Gear', false, false, null, true, 1095726380000),
  (1, 'Why You Should Go', 'Because youre a wimp', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Travel', false, true, 1895726380000, false, null),
  (1, 'Getting Over Some BS', 'Get under some broad', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Travel', false, false, null, true, 1195726380000),
  (1, 'Food Finds From Your Moms House', 'Tastes good man', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Gear', true, false, null, false, null),
  (1, 'Finding Peace', 'Dont even have to India', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Trekking', false, false, null, true, 1395726380000),
  (1, 'Scaling the Sky', 'Beat boredom with these journeys', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Biking', false, true, 1995726380000, false, null),
  (1, 'Cars, Trains, and Gangs', 'Staying safe on the road is harder than you thought', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Travel', false, false, null, true, 1495727380000),
  (1, 'Love Your Life', 'Schmarmy garbage', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Trekking', false, false, null, true, 1490726380000),
  (1, 'Another Blog Post', 'You better check this shit out', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Gear', false, true, 1995726380000, false, null),
  (1, 'Through the Looking Glass', 'Bring your spectacles', '<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris libero felis, maximus ut tincidunt a, consectetur in dolor. Pellentesque laoreet volutpat elit eget placerat. Pellentesque pretium molestie erat, vitae mollis urna dapibus a. Quisque eu aliquet metus. Aenean eget magna pharetra, mattis orci euismod, lobortis augue. Maecenas bibendum eros lorem, vitae pretium justo volutpat sit amet. Aenean varius odio magna, et pulvinar nulla sagittis a. Aliquam eleifend ac quam in pharetra. Praesent eu sem posuere, ultricies quam ullamcorper, eleifend est. In malesuada commodo eros non fringilla. Nulla aliquam diam et nisi pellentesque aliquet. Proin eu est commodo, molestie neque eu, faucibus leo.</p><p>Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Quisque hendrerit risus nulla, at congue dolor bibendum ac. Maecenas condimentum, orci non fringilla venenatis, justo dolor pellentesque enim, sit amet laoreet lectus risus et enim. Quisque a fringilla ex. Nunc at felis mauris. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Cras suscipit purus porttitor porta vestibulum. Vestibulum sed ipsum sit amet arcu mattis congue vitae ac risus. Phasellus ac ultrices est. Maecenas ultrices eros ligula. Quisque placerat nisi tellus, vel auctor ligula pretium et. Nullam turpis odio, tincidunt non eleifend eu, cursus id lorem. Nam nibh sapien, eleifend quis massa eu, vulputate ullamcorper odio.</p><p><img src="https://localtvkdvr.files.wordpress.com/2017/05/may-snow-toby-the-bernese-mountain-dog-at-loveland.jpg?quality=85&strip=all&w=2000" style="width: 300px;" class="fr-fic fr-fil fr-dii">Aenean viverra turpis urna, et pellentesque orci posuere non. Pellentesque quis condimentum risus, non mattis nulla. Integer posuere egestas elit, vitae semper libero blandit at. Aenean vehicula tortor nec leo accumsan lobortis. Pellentesque vitae eros non felis fermentum vehicula eu in libero. Etiam sed tortor id odio consequat tincidunt. Maecenas eu nibh maximus odio pulvinar tempus. Mauris ipsum neque, congue in laoreet eu, gravida ac dui. Nunc aliquet elit nec urna sagittis fermentum. Sed vehicula in leo a luctus. Sed commodo magna justo, sit amet aliquet odio mattis quis. Praesent eget vehicula erat. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam vel ipsum enim. Nulla facilisi.</p><p>Phasellus interdum felis sit amet finibus consectetur. Vivamus eget odio vel augue maximus finibus. Vestibulum fringilla lorem id lobortis convallis. Phasellus pharetra metus nec vulputate dapibus. Nunc id est mi. Vivamus placerat, diam sit amet sodales commodo, massa dolor euismod tortor, ut condimentum orci lectus ac ex. Ut mollis ex ut est euismod rhoncus. Quisque ut lobortis risus, a sodales diam. Maecenas vitae bibendum est, eget tincidunt lacus. Donec laoreet felis sed orci maximus, id consequat augue faucibus. In libero erat, porttitor vitae nunc id, dapibus sollicitudin nisl. Ut a pharetra neque, at molestie eros. Aliquam malesuada est rutrum nunc commodo, in eleifend nisl vestibulum.</p><p>Vestibulum id lacus rutrum, tristique lectus a, vestibulum odio. Nam dictum dui at urna pretium sodales. Nullam tristique nisi eget faucibus consequat. Etiam pretium arcu sed dapibus tincidunt. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus dictum vitae sapien suscipit dictum. In hac habitasse platea dictumst. Suspendisse risus dui, mattis ac malesuada efficitur, scelerisque vitae diam. Nam eu neque vel ex pharetra consequat vitae in justo. Phasellus convallis enim non est vulputate scelerisque. Duis id sagittis leo. Cras molestie tincidunt nisi, ac scelerisque est egestas vitae. Fusce mollis tempus dui in aliquet. Duis ipsum sem, ultricies nec risus nec, aliquet hendrerit neque. Integer accumsan varius iaculis.</p><p>Aliquam pharetra fringilla lectus sed placerat. Donec iaculis libero non sem maximus, id scelerisque arcu laoreet. Sed tempus eros sit amet justo posuere mollis. Etiam commodo semper felis maximus porttitor. Fusce ut molestie massa. Phasellus sem enim, tristique quis lorem id, maximus accumsan sapien. Aenean feugiat luctus ligula, vel tristique nunc convallis eget.</p><p>Ut facilisis tortor turpis, ac feugiat nunc egestas eget. Ut tincidunt ex nisi, eu egestas purus interdum in. Pellentesque ornare commodo turpis vitae aliquam. Etiam ornare cursus elit, in feugiat mauris ornare vitae. Morbi mollis molestie lacus, non pulvinar quam. Quisque eleifend sed erat id congue. Vivamus vulputate tempus tortor, a gravida justo dictum id. Proin tristique, neque id viverra accumsan, leo erat mattis sem, at porttitor nisi enim non risus. Nunc pharetra velit ut condimentum porta. Fusce consectetur id lectus quis vulputate. Nunc congue rutrum diam, at sodales magna malesuada iaculis. Aenean nec facilisis nulla, vestibulum eleifend purus.<img src="https://i.froala.com/assets/photo2.jpg" data-id="2" data-type="image" data-name="Image 2017-08-07 at 16:08:48.jpg" style="width: 300px;" class="fr-fic fr-dii hoverZoomLink fr-fir"></p><p>Morbi eget dolor sed velit pharetra placerat. Duis justo dui, feugiat eu diam ut, rutrum pellentesque urna. Praesent mattis tellus nec congue auctor. Fusce condimentum in sem at rhoncus. Mauris nec erat lacinia ligula viverra congue eget sit amet tellus. Aenean aliquet fermentum velit. Vivamus ut odio vel dolor mattis interdum. Nunc ullamcorper ex quis arcu tincidunt, sed accumsan massa rutrum. In at urna laoreet enim auctor consectetur ac eu justo. Curabitur porta turpis eget purus interdum scelerisque. Nunc dignissim aliquam sagittis. Suspendisse feugiat velit semper, condimentum magna vel, mollis neque. Maecenas sed lectus vel mi fringilla vehicula sit amet sed risus. Morbi posuere tincidunt magna nec interdum.</p><p>Mauris non cursus nisi, id semper quam. Aliquam auctor, est nec fringilla egestas, nisi orci varius sem, molestie faucibus est nulla ut tellus. Pellentesque in massa facilisis, sollicitudin elit nec, interdum ipsum. Maecenas pellentesque, orci sit amet auctor volutpat, mi lectus hendrerit arcu, nec pharetra justo justo et justo. Etiam feugiat dolor nisi, bibendum egestas leo auctor ut. Suspendisse dapibus quis purus nec pretium. Proin gravida orci et porta vestibulum. Cras ut sem in ante dignissim elementum vehicula id augue. Donec purus augue, dapibus in justo ut, posuere mollis felis. Nunc iaculis urna dolor, sollicitudin aliquam eros mattis placerat. Ut eget turpis ut dui ullamcorper ultricies a eget ex. Integer vitae lorem vel metus dignissim volutpat. Mauris tincidunt faucibus tellus, quis mollis libero. Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><p>Duis viverra efficitur libero eget luctus. Aenean dapibus sodales diam, posuere dictum erat rhoncus et. Interdum et malesuada fames ac ante ipsum primis in faucibus. Nullam ligula ex, tincidunt sed enim eget, accumsan luctus nulla. Mauris ac consequat nunc, et ultrices ipsum. Integer nec venenatis est. Vestibulum dapibus, velit nec efficitur posuere, urna enim pretium quam, sit amet malesuada orci nibh sed metus. Nulla nec eros felis. Sed imperdiet mauris id egestas suscipit. Nunc interdum laoreet maximus. Nunc congue sapien ultricies, pretium est nec, laoreet sem. Fusce ornare tortor massa, ac vestibulum enim gravida nec.</p>', 'Trekking', false, false, null, true, 1298726380000);

comment on table pomb.post is 'Table with POMB posts';
comment on column pomb.post.id is 'Primary id for post';
comment on column pomb.post.title is 'Title of the post';
comment on column pomb.post.subtitle is 'Subtitle of post';
comment on column pomb.post.content is 'Content of post';
comment on column pomb.post.category is 'Category of post';
comment on column pomb.post.is_draft is 'Post is a draft';
comment on column pomb.post.is_scheduled is 'Post is scheduled';
comment on column pomb.post.scheduled_date is 'Date post is scheduled';
comment on column pomb.post.is_published is 'Post is published';
comment on column pomb.post.published_date is 'Date post is published';
comment on column pomb.post.created_at is 'When post created';
comment on column pomb.post.updated_at is 'Last updated date';

--alter table pomb.post enable row level security;

create table pomb.post_tag (
  id                  serial primary key,
  name                text not null,
  tag_description     text
);

insert into pomb.post_tag (name, tag_description) values
  ('colombia', 'What was once a haven for drugs and violence, Colombia has become a premiere destination for those who seek adventure, beauty, and intrepid charm.'),
  ('buses', 'No easier way to see a place than with your fellow man then round and round'),
  ('diving', 'Underneath the surf is a whole world to explore, find it.'),
  ('camping', 'Have no fear, the camping hub is here. Learn tips for around the site, checkout cool spots, and find how to make the most of your time in the outdoors.'),
  ('food', 'There are few things better than exploring the food on offer throughout the world and in your backyard. The food hub has you covered to find your next craving.'),
  ('sports', 'Theres more than just NFL football out there, lets see what is in store.'),
  ('drinks', 'From fire water, to fine wine, to whiskey from the barrel. Spirits a-plenty to sate any thirst.'),
  ('nightlife', 'Thumping beats, starry sights, and friendly people make a night on the town an integral part of any journey.');

comment on table pomb.post_tag is 'Table with the type of post tags available';
comment on column pomb.post_tag.id is 'Primary id for the tag';
comment on column pomb.post_tag.name is 'Name of the post tag';
comment on column pomb.post_tag.tag_description is 'Description of the post tag';

create table pomb.post_to_tag ( --one to many
  id                 serial primary key,
  post_id            integer not null references pomb.post(id) on delete cascade,
  post_tag_id        integer not null references pomb.post_tag(id) on delete cascade
);

insert into pomb.post_to_tag (post_id, post_tag_id) values
  (1, 1),
  (1, 4),
  (2, 7),
  (3, 1),
  (3, 3),
  (3, 5),
  (4, 7),
  (4, 3),
  (5, 2),
  (5, 7),
  (6, 4),
  (7, 2),
  (8, 1),
  (9, 1),
  (10, 7),
  (11, 8),
  (11, 5),
  (12, 8),
  (12, 3),
  (13, 4),
  (13, 5),
  (13, 8);

comment on table pomb.post_to_tag is 'Join table for tags on a post';
comment on column pomb.post_to_tag.id is 'Id of the row';
comment on column pomb.post_to_tag.post_id is 'Id of the post';
comment on column pomb.post_to_tag.post_tag_id is 'Id of the post tag';

create table pomb.post_comment (
  id                  serial primary key,
  author              integer not null references pomb.account(id),
  content             text not null,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

insert into pomb.post_comment (author, content) values
  (1, 'Colombia commentary'),
  (1, 'Biking Bizness'),
  (1, 'Hiking is neat'),
  (1, 'Camping is fun'),
  (1, 'Food is dope'),
  (1, 'Travel is lame'),
  (1, 'Culture is exotic'),
  (1, 'Gear snob');

comment on table pomb.post_comment is 'Table with comments from users';
comment on column pomb.post_comment.id is 'Primary id for the comment';
comment on column pomb.post_comment.author is 'Primary id of author';
comment on column pomb.post_comment.content is 'Body of the comment';
comment on column pomb.post_comment.created_at is 'Time comment created at';
comment on column pomb.post_comment.updated_at is 'Time comment updated at';

create table pomb.post_to_comment ( --one to many
  post_id            integer not null references pomb.post(id) on delete cascade,
  comment_id         integer not null references pomb.post_comment(id)
);

insert into pomb.post_to_comment (post_id, comment_id) values
  (1, 1),
  (1, 4),
  (2, 7),
  (3, 1),
  (3, 3),
  (3, 5),
  (4, 7),
  (4, 3),
  (5, 2);

comment on table pomb.post_to_comment is 'Join table for comments on a post';
comment on column pomb.post_to_comment.post_id is 'Id of the post';
comment on column pomb.post_to_comment.comment_id is 'Id of the comment';

create table pomb.trip (
  id                  serial primary key,
  user_id             integer not null references pomb.account(id) on delete cascade,
  name                text not null check (char_length(name) < 256),
  start_date          bigint not null,
  end_date            bigint,
  start_lat           decimal not null,
  start_lon           decimal not null,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

insert into pomb.trip (user_id, name, start_date, end_date, start_lat, start_lon) values
  (1, 'Cool Trip', 1508274574542, 1548282774542, 37.7749, -122.4194),
  (1, 'Neat Trip', 1408274574542, 1448274574542, 6.2442, -75.5812);

comment on table pomb.trip is 'Table with POMB trips';
comment on column pomb.trip.id is 'Primary id for trip';
comment on column pomb.trip.user_id is 'User id who created trip';
comment on column pomb.trip.name is 'Name of trip';
comment on column pomb.trip.start_date is 'Start date of trip';
comment on column pomb.trip.end_date is 'End date of trip';
comment on column pomb.trip.start_lat is 'Starting point latitude of trip';
comment on column pomb.trip.start_lon is 'Starting poiht longitude of trip';
comment on column pomb.trip.created_at is 'When trip created';
comment on column pomb.trip.updated_at is 'When trip last updated';

create table pomb.juncture (
  id                  serial primary key,
  user_id             integer not null references pomb.account(id) on delete cascade,
  trip_id             integer not null references pomb.trip(id) on delete cascade,
  name                text not null check (char_length(name) < 256),
  arrival_date        bigint not null,
  description         text check (char_length(name) < 1200),
  lat                 decimal not null,
  lon                 decimal not null,
  city                text,
  country             text,
  is_draft            boolean,
  marker_img          text,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

insert into pomb.juncture (user_id, trip_id, name, arrival_date, description, lat, lon, city, country, is_draft, marker_img) values
  (1, 1, 'Day 1', 1508274574542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 36.9741, -122.0308, 'Santa Cruz', 'United States', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 2', 1508274774542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 37.7749, -122.4194, 'San Francisco', 'United States', true, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 3', 1508278774542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 37.9735, -122.5311, 'San Rafael', 'United States', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 4', 1508278874542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 38.4741, -119.0308, 'Whichman', 'United States', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 5', 1528279074542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 38.7749, -118.4194, 'Walter Lake', 'United States', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 6', 1528279874542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 39.9735, -110.5311, 'Myron', 'United States', false, null),
  (1, 1, 'Day 7', 1538280574542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 40.9741, -108.0308, 'Baggs', 'United States', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 8', 1538281674542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 41.7749, -108.4194, 'Rock Springs', 'United States', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png'),
  (1, 1, 'Day 9', 1548282774542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 39.9735, -114.5311, 'Cherry Creek', 'United States', false, null),
  (1, 2, 'So it begins', 1408274584542, 'Proin pulvinar non leo sit amet tempor. Curabitur auctor, justo in ullamcorper posuere, velit arcu scelerisque nisl, sit amet vulputate urna est vel mi. Mauris eleifend dolor sit amet tempus eleifend. Aliquam finibus nisl a tortor consequat, quis rhoncus nunc consectetur. Duis velit dui, aliquam id dictum at, molestie sed arcu. Ut imperdiet mauris elit. Integer maximus, augue eu iaculis tempus, nisl libero faucibus magna, et ultricies sem est vitae erat. Phasellus vitae pulvinar lorem. Sed consectetur eu quam non blandit. Ut tincidunt lacus sed tortor ultrices, et laoreet purus ornare. Donec vestibulum metus a ullamcorper iaculis. Donec fermentum est metus, non scelerisque risus vestibulum ac. Suspendisse euismod volutpat nisl vitae euismod. Duis convallis, est id ornare malesuada, lorem urna mattis risus, eu semper elit sem fringilla risus. Nunc porta, sapien sit amet accumsan fermentum, augue nulla congue diam, et lobortis ante ante eget est. Mauris placerat nisl id consequat laoreet.', 4.7110, -74.0721, 'Medellin', 'Colombia', false, 'https://packonmyback.s3.amazonaws.com/WP_20150721_08_47_08_Pro__highres-marker-1515559581861.png');

comment on table pomb.juncture is 'Table with POMB junctures';
comment on column pomb.juncture.id is 'Primary id for juncture';
comment on column pomb.juncture.user_id is 'User id who created juncture';
comment on column pomb.juncture.trip_id is 'Trip id juncture belongs to';
comment on column pomb.juncture.name is 'Name of juncture';
comment on column pomb.juncture.arrival_date is 'Date of juncture';
comment on column pomb.juncture.description is 'Description of the juncture';
comment on column pomb.juncture.lat is 'Latitude of the juncture';
comment on column pomb.juncture.lon is 'Longitude of the juncture';
comment on column pomb.juncture.city is 'City of the juncture';
comment on column pomb.juncture.country is 'Country of the juncture';
comment on column pomb.juncture.is_draft is 'Whether the juncture should be published or not';
comment on column pomb.juncture.marker_img is 'Image to be used for markers on our map';
comment on column pomb.juncture.created_at is 'When juncture created';
comment on column pomb.juncture.updated_at is 'When juncture last updated';

create table pomb.juncture_to_post (
  id                 serial primary key,
  juncture_id        integer not null references pomb.juncture(id) on delete cascade,
  post_id            integer not null references pomb.post(id) on delete cascade
);

insert into pomb.juncture_to_post (juncture_id, post_id) values
  (1, 1),
  (1, 4),
  (2, 2);

comment on table pomb.juncture_to_post is 'Join table for posts related to a juncture';
comment on column pomb.juncture_to_post.id is 'Id of the row';
comment on column pomb.juncture_to_post.juncture_id is 'Id of the juncture';
comment on column pomb.juncture_to_post.post_id is 'Id of the post';

create table pomb.coords (
  id                  serial primary key,
  juncture_id         integer not null references pomb.juncture(id) on delete cascade,
  lat                 decimal not null,
  lon                 decimal not null,
  elevation           decimal,
  coord_time          timestamp
);

comment on table pomb.coords is 'Table with POMB juncture coordinates';
comment on column pomb.coords.id is 'Primary id for coordinates';
comment on column pomb.coords.juncture_id is 'Foreign key to referred juncture';
comment on column pomb.coords.lat is 'Latitude of coords';
comment on column pomb.coords.lon is 'Longitude of coords';
comment on column pomb.coords.elevation is 'Elevation of coords';
comment on column pomb.coords.coord_time is 'Timestamp of coords';

create table pomb.email_list (
  id                  serial primary key,
  email               text not null unique check (char_length(email) < 256),
  created_at          bigint default (extract(epoch from now()) * 1000)
);

comment on table pomb.email_list is 'Table with POMB list of emails';
comment on column pomb.email_list.id is 'Primary id for email';
comment on column pomb.email_list.email is 'Email of user';
comment on column pomb.email_list.created_at is 'When email created';

-- Limiting choices for type field on image
create type pomb.image_type as enum (
  'leadLarge',
  'leadSmall',
  'gallery',
  'banner'
);

create table pomb.image (
  id                  serial primary key,
  trip_id             integer references pomb.trip(id) on delete cascade,
  juncture_id         integer references pomb.juncture(id) on delete cascade,
  post_id             integer references pomb.post(id) on delete cascade,
  user_id             integer not null references pomb.account(id) on delete cascade,
  type                pomb.image_type not null,
  url                 text not null,
  title               text check (char_length(title) < 80),
  description         text,
  created_at          bigint default (extract(epoch from now()) * 1000),
  updated_at          timestamp default now()
);

insert into pomb.image (trip_id, juncture_id, post_id, user_id, type, url, title, description) values
  (1, 1, 1, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Colombia commentary'),
  (1, 2, 2, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Biking Bizness'),
  (null, null, 3, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Hiking is neat'),
  (1, 1, 4, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Camping is fun'),
  (null, null, 5, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Food is dope'),
  (null, null, 6, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Travel is lame'),
  (null, null, 7, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 8, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 9, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 10, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 11, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 12, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 13, 1, 'leadLarge', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Gear snob'),
  (1, 1, 1, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Colombia commentary'),
  (1, 2, 2, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Biking Bizness'),
  (null, null, 3, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Hiking is neat'),
  (1, 1, 4, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Camping is fun'),
  (null, null, 5, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Food is dope'),
  (null, null, 6, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Travel is lame'),
  (null, null, 7, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 8, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 9, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 10, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 11, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 12, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Culture is exotic'),
  (null, null, 13, 1, 'leadSmall', 'http://images.singletracks.com/blog/wp-content/uploads/2016/06/Scale-Action-Image-2017-BIKE-SCOTT-Sports_9-1200x800.jpg', 'Dat photo title', 'Gear snob'),
  (1, 1, 1, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/c/ce/Lower_Yellowstone_Fall-1200px.jpg', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/01/coralbay-3579-1200px-wm-1.png', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'http://richard-western.co.uk/wp-content/uploads/2015/06/4.-PG9015-30-1200px.jpg', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/10/coralbay-4077-1200px-wm.png', null, 'A beautiful vista accented by your mom'),
  (1, 1, 1, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg/1200px-Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg', null, 'A beautiful vista accented by your mom'),
  (null, null, 3, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, 'A beautiful vista accented by your mom'),
  (null, null, 3, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, 'A beautiful vista accented by your mom'),
  (1, null, null, 1, 'banner', 'https://www.yosemitehikes.com/images/wallpaper/yosemitehikes.com-bridalveil-winter-1200x800.jpg', null, null),
  (1, null, null, 1, 'banner', 'https://lonelyplanetimages.imgix.net/a/g/hi/t/4ad86c274b7e632de388dcaca5236ca8-asia.jpg', null, null),
  (1, null, null, 1, 'banner', 'https://lonelyplanetimages.imgix.net/a/g/hi/t/1dd17a448edb6c7ced392c6a7ea1c0ac-asia.jpg', null, null),
  (1, null, null, 1, 'banner', 'https://lonelyplanetimages.imgix.net/a/g/hi/t/b3960ccbee8a59ce113d0cce9f53f283-asia.jpg', null, null),
  (1, 1, null, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, null),
  (1, 1, null, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/c/ce/Lower_Yellowstone_Fall-1200px.jpg', null, null),
  (1, 1, null, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/01/coralbay-3579-1200px-wm-1.png', null, null),
  (1, 2, null, 1, 'gallery', 'https://upload.wikimedia.org/wikipedia/commons/thumb/5/51/Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg/1200px-Sign_of_Brno_University_of_Technology_at_building_in_Brno%2C_Kr%C3%A1lovo_Pole.jpg', null, null),
  (1, 3, null, 1, 'gallery', 'https://d15shllkswkct0.cloudfront.net/wp-content/blogs.dir/1/files/2015/03/1200px-Hommik_Viru_rabas.jpg', null, null),
  (1, 3, null, 1, 'gallery', 'http://www.ningalooreefdive.com/wp-content/uploads/2014/01/coralbay-3579-1200px-wm-1.png', null, null);

comment on table pomb.image is 'Table with site images';
comment on column pomb.image.id is 'Primary id for the photo';
comment on column pomb.image.trip_id is 'Primary id of trip its related to';
comment on column pomb.image.juncture_id is 'Primary id of juncture its related to';
comment on column pomb.image.post_id is 'Primary id of post its related to';
comment on column pomb.image.user_id is 'Primary id of user who uploaded image';
comment on column pomb.image.type is 'Type of image';
comment on column pomb.image.url is 'Link to image';
comment on column pomb.image.title is 'Title of image';
comment on column pomb.image.description is 'Description of image';
comment on column pomb.image.created_at is 'Time comment created at';
comment on column pomb.image.updated_at is 'Time comment updated at';

create table pomb.config (
  id                  serial primary key,
  primary_color       text not null check (char_length(primary_color) < 20),
  secondary_color     text not null check (char_length(secondary_color) < 20),
  tagline             text not null check (char_length(tagline) < 80),
  hero_banner         text not null,
  featured_story_1    integer not null references pomb.post(id),
  featured_story_2    integer not null references pomb.post(id),
  featured_story_3    integer not null references pomb.post(id),
  featured_trip_1     integer not null references pomb.trip(id),
  updated_at          timestamp default now()
);

insert into pomb.config (primary_color, secondary_color, tagline, hero_banner, featured_story_1, featured_story_2, featured_story_3, featured_trip_1) values
  ('#e1ff00', '#04c960', 'For wherever the road takes you', 'http://www.pinnaclepellet.com/images/1200x300-deep-forest.jpg', 4, 8, 13, 1);

comment on table pomb.config is 'Table with POMB config';
comment on column pomb.config.id is 'Id for config';
comment on column pomb.config.primary_color is 'Primary color for site';
comment on column pomb.config.secondary_color is 'Secondary color for site';
comment on column pomb.config.tagline is 'Tagline of site';
comment on column pomb.config.hero_banner is 'Hero banner url';
comment on column pomb.config.featured_story_1 is 'Featured story for nav';
comment on column pomb.config.featured_story_2 is 'Featured story for nav';
comment on column pomb.config.featured_story_3 is 'Featured story for nav';
comment on column pomb.config.featured_trip_1 is 'Featured trip for nav';
comment on column pomb.config.updated_at is 'Last updated';

-- *******************************************************************
-- *********************** Function Queries **************************
-- *******************************************************************
CREATE FUNCTION pomb.posts_by_tag(tag_id INTEGER) returns setof pomb.post AS $$
  SELECT pomb.post.* 
  FROM pomb.post 
  INNER JOIN pomb.post_to_tag ON pomb.post.id = pomb.post_to_tag.post_id 
  WHERE pomb.post_to_tag.post_tag_id = tag_id;
$$ language sql stable;

COMMENT ON FUNCTION pomb.posts_by_tag(INTEGER) is 'Returns posts that include a given tag';

create function pomb.search_tags(query text) returns setof pomb.post_tag as $$
  select post_tag.*
  from pomb.post_tag as post_tag
  where post_tag.name ilike ('%' || query || '%')
$$ language sql stable;

comment on function pomb.search_tags(text) is 'Returns tags containing a given query term.';

-- *******************************************************************
-- ************************* Triggers ********************************
-- *******************************************************************
create function pomb_private.set_updated_at() returns trigger as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$ language plpgsql;

create trigger post_updated_at before update
  on pomb.post
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger account_updated_at before update
  on pomb.account
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger comment_updated_at before update
  on pomb.post_comment
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger config_updated_at before update
  on pomb.config
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger trip_updated_at before update
  on pomb.trip
  for each row
  execute procedure pomb_private.set_updated_at();

create trigger juncture_updated_at before update
  on pomb.juncture
  for each row
  execute procedure pomb_private.set_updated_at();

  create trigger image_updated_at before update
  on pomb.image
  for each row
  execute procedure pomb_private.set_updated_at();

-- *******************************************************************
-- *********************** FTS ***************************************
-- *******************************************************************

-- Once an index is created, no further intervention is required: the system will update the index when the table is modified, and it will use the index in queries when it 
-- thinks doing so would be more efficient than a sequential table scan. But you might have to run the ANALYZE command regularly to update statistics to allow the query planner 
-- to make educated decisions. See Chapter 14 for information about how to find out whether an index is used and when and why the planner might choose not to use an index.

-- Below creates a materialized view to allow for indexing across tables

CREATE MATERIALIZED VIEW pomb.post_search_index AS
SELECT pomb.post.*,
  setweight(to_tsvector('english', pomb.post.title), 'A') || 
  setweight(to_tsvector('english', pomb.post.subtitle), 'B') ||
  setweight(to_tsvector('english', pomb.post.content), 'C') ||
  setweight(to_tsvector('english', pomb.post.category::text), 'D') ||
  setweight(to_tsvector('english', pomb.post_tag.name), 'D') as document
FROM pomb.post
JOIN pomb.post_to_tag ON pomb.post_to_tag.post_id = pomb.post.id
JOIN pomb.post_tag ON pomb.post_tag.id = pomb.post_to_tag.post_tag_id
-- JOIN pomb.post_to_category ON pomb.post_to_category.post_id = pomb.post.id
-- JOIN pomb.post_category ON pomb.post_category.id = pomb.post_to_category.post_category_id
GROUP BY pomb.post.id, pomb.post_tag.id; 

CREATE INDEX idx_post_search ON pomb.post_search_index USING gin(document);

-- Then reindexing the search engine will be as simple as periodically running REFRESH MATERIALIZED VIEW post_search_index;

-- Trip search searches through trips && junctures

CREATE MATERIALIZED VIEW pomb.trip_search_index AS
SELECT pomb.trip.*,
  setweight(to_tsvector('english', pomb.trip.name), 'A') ||
  setweight(to_tsvector('english', pomb.juncture.name), 'B') ||
  setweight(to_tsvector('english', pomb.juncture.description), 'C') ||
  setweight(to_tsvector('english', pomb.juncture.city), 'D') ||
  setweight(to_tsvector('english', pomb.juncture.country), 'D') as document
FROM pomb.trip
JOIN pomb.juncture ON pomb.juncture.trip_id = pomb.trip.id
GROUP BY pomb.trip.id, pomb.juncture.id;

CREATE INDEX idx_trip_search ON pomb.trip_search_index USING gin(document);

CREATE MATERIALIZED VIEW pomb.account_search_index AS
SELECT pomb.account.*,
  setweight(to_tsvector('english', pomb.account.username), 'A') ||
  setweight(to_tsvector('english', pomb.account.first_name), 'B') ||
  setweight(to_tsvector('english', pomb.account.last_name), 'B') as document
FROM pomb.account;

CREATE INDEX idx_account_search ON pomb.account_search_index USING gin(document);

-- Simple (instead of english) is one of the built in search text configs that Postgres provides. simple doesn't ignore stopwords and doesn't try to find the stem of the word. 
-- With simple every group of characters separated by a space is a lexeme; the simple text search config is pratical for data like a person's name for which we may not want to find the stem of the word.

create function pomb.search_posts(query text) returns setof pomb.post_search_index as $$

  SELECT post FROM (
    SELECT DISTINCT ON(post.id) post, max(ts_rank(document, to_tsquery('english', query)))
      FROM pomb.post_search_index as post
      WHERE document @@ to_tsquery('english', query)
    GROUP BY post.id, post.*
    order by post.id, max DESC
  ) search_results
  order by search_results.max DESC;

$$ language sql stable;

comment on function pomb.search_posts(text) is 'Returns posts given a search term.';

create function pomb.search_trips(query text) returns setof pomb.trip_search_index as $$

  SELECT trip FROM (
    SELECT DISTINCT ON(trip.id) trip, max(ts_rank(document, to_tsquery('english', query)))
      FROM pomb.trip_search_index as trip
      WHERE document @@ to_tsquery('english', query)
    GROUP BY trip.id, trip.*
    order by trip.id, max DESC
  ) search_results
  order by search_results.max DESC;

$$ language sql stable;

comment on function pomb.search_trips(text) is 'Returns trips given a search term.';

create function pomb.search_accounts(query text) returns setof pomb.account_search_index as $$

  SELECT account FROM (
    SELECT DISTINCT ON(account.id) account, max(ts_rank(document, to_tsquery('english', query)))
      FROM pomb.account_search_index as account
      WHERE document @@ to_tsquery('english', query)
    GROUP BY account.id, account.*
    order by account.id, max DESC
  ) search_results
  order by search_results.max DESC;

$$ language sql stable;

comment on function pomb.search_accounts(text) is 'Returns accounts given a search term.';

-- *******************************************************************
-- ************************* Auth ************************************
-- *******************************************************************

create table pomb_private.user_account (
  account_id          integer primary key references pomb.account(id) on delete cascade,
  email               text not null unique check (email ~* '^.+@.+\..+$'),
  password_hash       text not null
);

comment on table pomb_private.user_account is 'Private information about a user’s account.';
comment on column pomb_private.user_account.account_id is 'The id of the user associated with this account.';
comment on column pomb_private.user_account.email is 'The email address of the account.';
comment on column pomb_private.user_account.password_hash is 'An opaque hash of the account’s password.';

create extension if not exists "pgcrypto";

create function pomb.register_account (
  username            text,
  first_name          text,
  last_name           text,
  email               text,
  password            text
) returns pomb.account as $$
declare
  account pomb.account;
begin
  insert into pomb.account (username, first_name, last_name) values
    (username, first_name, last_name)
    returning * into account;

  insert into pomb_private.user_account (account_id, email, password_hash) values
    (account.id, email, crypt(password, gen_salt('bf')));

  return account;
end;
$$ language plpgsql strict security definer;

comment on function pomb.register_account(text, text, text, text, text) is 'Registers and creates an account for POMB.';

-- *******************************************************************
-- ************************* Roles ************************************
-- *******************************************************************

create role pomb_admin login password 'abc123';
GRANT ALL privileges ON ALL TABLES IN SCHEMA pomb to pomb_admin;
GRANT ALL privileges ON ALL TABLES IN SCHEMA pomb_private to pomb_admin;

create role pomb_anonymous login password 'abc123' NOINHERIT;
GRANT pomb_anonymous to pomb_admin; --Now, the pomb_admin role can control and become the pomb_anonymous role. If we did not use that GRANT, we could not change into the pomb_anonymous role in PostGraphQL.

create role pomb_account;
GRANT pomb_account to pomb_admin; --The pomb_admin role will have all of the permissions of the roles GRANTed to it. So it can do everything pomb_anonymous can do and everything pomb_usercan do.
GRANT pomb_account to pomb_anonymous; 

create type pomb.jwt_token as (
  role text,
  account_id integer
);

alter database bclynch set "jwt.claims.account_id" to '0';

create function pomb.authenticate_account(
  email text,
  password text
) returns pomb.jwt_token as $$
declare
  account pomb_private.user_account;
begin
  select a.* into account
  from pomb_private.user_account as a
  where a.email = $1;

  if account.password_hash = crypt(password, account.password_hash) then
    return ('pomb_account', account.account_id)::pomb.jwt_token;
  else
    return null;
  end if;
end;
$$ language plpgsql strict security definer;

comment on function pomb.authenticate_account(text, text) is 'Creates a JWT token that will securely identify an account and give them certain permissions.';

create function pomb.current_account() returns pomb.account as $$
  select *
  from pomb.account
  where pomb.account.id = current_setting('jwt.claims.account_id', true)::integer
$$ language sql stable;

comment on function pomb.current_account() is 'Gets the account that was identified by our JWT.';

-- *******************************************************************
-- ************************* Security *********************************
-- *******************************************************************

GRANT usage on schema pomb to pomb_anonymous, pomb_account;
GRANT usage on all sequences in schema pomb to pomb_account;

GRANT ALL on table pomb.post to pomb_account; --ultimately needs to be policy in which only own user!
GRANT ALL on table pomb.post_tag to pomb_account;
GRANT ALL on table pomb.post_to_tag to pomb_account; --ultimately needs to be policy in which only own user!
GRANT ALL ON TABLE pomb.trip TO pomb_account; --ultimately needs to be policy in which only own user!
GRANT ALL ON TABLE pomb.juncture TO pomb_account; --ultimately needs to be policy in which only own user!
GRANT ALL ON TABLE pomb.juncture_to_post TO pomb_account; --ultimately needs to be policy in which only own user!
GRANT ALL ON TABLE pomb.coords TO PUBLIC; --Need to figure this out... Inserting from node
GRANT ALL ON TABLE pomb.email_list TO PUBLIC; --Need to figure this out... Inserting from node

GRANT select on table pomb.post to PUBLIC;
GRANT select on table pomb.post_tag to PUBLIC;
GRANT select on table pomb.post_to_tag to PUBLIC;
GRANT select on table pomb.post_comment to PUBLIC;
GRANT select on table pomb.post_to_comment to PUBLIC;
GRANT select on table pomb.account to PUBLIC;
GRANT select on table pomb.image to PUBLIC;
GRANT SELECT ON TABLE pomb.trip TO PUBLIC;
GRANT SELECT ON TABLE pomb.juncture TO PUBLIC;
GRANT SELECT ON TABLE pomb.juncture_to_post TO PUBLIC;

GRANT ALL on table pomb.config to PUBLIC; -- ultimately needs to only be admin account that can mod
GRANT ALL on table pomb.account to pomb_account; --ultimately needs to be policy in which only own user!
GRANT select on pomb.post_search_index to PUBLIC;
GRANT select on pomb.trip_search_index to PUBLIC;
GRANT select on pomb.account_search_index to PUBLIC;

GRANT execute on function pomb.register_account(text, text, text, text, text) to pomb_anonymous;
GRANT execute on function pomb.authenticate_account(text, text) to pomb_anonymous;
GRANT execute on function pomb.current_account() to PUBLIC;
GRANT execute on function pomb.posts_by_tag(integer) to PUBLIC;
GRANT execute on function pomb.search_tags(text) to PUBLIC;
GRANT execute on function pomb.search_posts(text) to PUBLIC;
GRANT execute on function pomb.search_trips(text) to PUBLIC; 
GRANT execute on function pomb.search_accounts(text) to PUBLIC;  

-- ///////////////// RLS Policies ////////////////////////////////

-- Can make it an 'all' by omitting the for ... (update) statement
-- Can only do one type of method per policy

-- --only user can edit account
-- create policy account_update on pomb.account for UPDATE to pomb_account
--   using (id = current_setting('jwt.claims.account_id')::integer);

-- -- only user can edit, delete posts
-- create policy account_post_update on pomb.post for UPDATE to pomb_account
--   using (id = current_setting('jwt.claims.account_id')::integer);

-- create policy account_post_delete on pomb.post for DELETE to pomb_account
--   using (id = current_setting('jwt.claims.account_id')::integer);


commit;