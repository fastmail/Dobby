use v5.36.0;
use utf8;

use Dobby::Boxmate::App::Command::ciplan;

use Getopt::Long::Descriptive;
use Path::Tiny;
use Test::More;
use Test::Deep ':v1';

my $CMD = 'Dobby::Boxmate::App::Command::ciplan';

# The template program reads the environment to decide what to do, so every
# test starts from a known-empty environment rather than whatever the person
# running the tests happens to have exported.
my @CI_ENV = qw(
  ME_TEST_SLOW
  CI_MERGE_REQUEST_SOURCE_PROJECT_PATH
  CI_MERGE_REQUEST_SOURCE_BRANCH_NAME
);

# Build the program the way the command really would: by handing the command's
# own opt_spec to Getopt::Long::Descriptive, so that the spelling of the
# command line switch is under test too, not just the accessor behind it.
my sub program_for ($env, $argv) {
  local @ENV{ @CI_ENV };
  delete @ENV{ @CI_ENV };
  $ENV{ME_TEST_SLOW} = $env if defined $env;

  local @ARGV = @$argv;
  my ($opt, undef) = describe_options('%c %o', $CMD->opt_spec);

  return $CMD->_template_program($opt);
}

my sub step_named ($program, $name) {
  my ($step) = grep {; $_->[0] eq $name } @$program;
  return $step;
}

sub newt_args_ok ($env, $argv, $expect, $desc) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $step = step_named(program_for($env, $argv), 'newt_full');

  cmp_deeply(
    [ @{$step}[ 1 .. $#$step ] ],
    $expect,
    $desc,
  );
}

newt_args_ok(undef, [], [], 'by default, slow tests are left out');

newt_args_ok(undef, ['--include-slow-tests'], ['slow'],
  '--include-slow-tests asks for them');

newt_args_ok(1, [], ['slow'],
  'ME_TEST_SLOW=1 asks for them, as the nightly job does');

newt_args_ok(0, [], [],
  'ME_TEST_SLOW=0 is as good as leaving it unset');

newt_args_ok('', [], [],
  'an empty ME_TEST_SLOW is as good as leaving it unset');

newt_args_ok(0, ['--include-slow-tests'], ['slow'],
  'an explicit switch beats a false ME_TEST_SLOW');

subtest 'asking for slow tests changes nothing but the newt_full step' => sub {
  my $without = program_for(undef, []);
  my $with    = program_for(undef, ['--include-slow-tests']);

  cmp_deeply(
    [ map {; $_->[0] } @$with ],
    [ map {; $_->[0] } @$without ],
    'the same steps, in the same order',
  );

  cmp_deeply(
    [ grep {; $_->[0] ne 'newt_full' } @$with ],
    [ grep {; $_->[0] ne 'newt_full' } @$without ],
    'and every other step takes the same arguments',
  );
};

# The test runner dies at the point of use on a step it does not implement, by
# which time we have paid for a bunch of droplet time.  Until it validates the
# whole program up front, this stands in for that check.
subtest 'every step in the template is one the runner implements' => sub {
  my $runner = path('misc/test-runner-on-vm');

  unless (-r $runner) {
    plan skip_all => "can't read $runner";
  }

  my %implemented = map  {; $_ => 1 }
                    ($runner->slurp_utf8 =~ /^sub STEP_(\w+)/gm);

  ok(keys %implemented, 'we found step implementations to check against');

  for my $step (program_for(undef, ['--include-slow-tests'])->@*) {
    ok($implemented{ $step->[0] }, "the runner implements the $step->[0] step");
  }
};

done_testing;
