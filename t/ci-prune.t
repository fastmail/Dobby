use v5.36.0;
use utf8;

use Dobby::Boxmate::App::Command::ciprune;

use Test::More;
use Test::Deep ':v1';

my $CMD = 'Dobby::Boxmate::App::Command::ciprune';

my $NOW = 1767225600; # 2026-01-01T00:00:00Z

# Droplets are named for their age in hours, so the expectations below read as
# "these are the boxes this many hours old".
my sub droplet ($name, $hours_old) {
  my @t = gmtime($NOW - $hours_old * 3600);

  return {
    id         => $hours_old,
    name       => $name,
    created_at => sprintf('%04u-%02u-%02uT%02u:%02u:%02uZ',
                    $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]),
  };
}

my @DROPLETS = (
  droplet('ci-run-1000.jane.fm.example.com',  1),
  droplet('ci-run-1001.jane.fm.example.com',  6),
  droplet('ci-run-1002.jane.fm.example.com',  7),
  droplet('ci-run-1003.jane.fm.example.com', 48),
  droplet('jane.fm.example.com',             48),
  droplet('not-ci-run-1004.fm.example.com',  48),
  droplet('ci-run.fm.example.com',           48),
);

my sub sort_boxes ($max_age_hours) {
  return $CMD->sort_boxes_to_prune({
    droplets => \@DROPLETS,
    now      => $NOW,
    max_age  => $max_age_hours * 3600,
  });
}

sub prunable_ok ($max_age_hours, $expect, $desc) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my (undef, $doomed) = sort_boxes($max_age_hours);

  cmp_deeply(
    [ map {; $_->{droplet}{name} } @$doomed ],
    $expect,
    $desc,
  );
}

prunable_ok(6, [
  'ci-run-1003.jane.fm.example.com',
  'ci-run-1002.jane.fm.example.com',
], 'six hours: only the CI boxes older than six hours, oldest first');

prunable_ok(24, [
  'ci-run-1003.jane.fm.example.com',
], 'one day: only the two-day-old CI box');

prunable_ok(72, [], 'three days: nothing is old enough to prune');

prunable_ok(0, [
  'ci-run-1003.jane.fm.example.com',
  'ci-run-1002.jane.fm.example.com',
  'ci-run-1001.jane.fm.example.com',
  'ci-run-1000.jane.fm.example.com',
], 'no minimum age: every CI box, and only the CI boxes');

subtest 'the CI boxes we find, doomed or not' => sub {
  my ($ci_boxes) = sort_boxes(6);

  cmp_deeply(
    [ map {; [ $_->{droplet}{name}, $_->{age} ] } @$ci_boxes ],
    [
      [ 'ci-run-1003.jane.fm.example.com', 48*3600 ],
      [ 'ci-run-1002.jane.fm.example.com',  7*3600 ],
      [ 'ci-run-1001.jane.fm.example.com',  6*3600 ],
      [ 'ci-run-1000.jane.fm.example.com',  1*3600 ],
    ],
    'we find every CI box, oldest first, with its age in seconds',
  );
};

done_testing;
