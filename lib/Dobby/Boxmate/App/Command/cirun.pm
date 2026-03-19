package Dobby::Boxmate::App::Command::cirun;
use Dobby::Boxmate::App -command;

# ABSTRACT: inject CI runner into remote box

use v5.36.0;
use utf8;

sub command_names {
  return qw(ci-run cirun);
}

sub abstract { 'inject CI runner into remote box' }

sub usage_desc {
  '%c ci-inject %o PLANFILE',
}

sub opt_spec {
  return (
    [ 'taskstream|S', 'expect TASK:: protocol directives in the output' ],
    [ 'username=s',   "put the box in this user's namespace", { default => $ENV{USER} }, ],
  );
}

sub validate_args ($self, $opt, $args) {
  @$args == 1 || $self->usage->die;

  my $plan_file = $args->[0];
  -r $plan_file || die "Can't read plan file $plan_file!\n";

  $opt->username
    || $self->usage->die({ pre_text => "Neither --username nor \$USER was supplied.\n\n" });
}

sub execute ($self, $opt, $args) {
  my $ip;

  unless (-e -r "misc/test-runner-on-vm") {
    die "Can't find the CI program we want to inject!\n";
  }

  require Path::Tiny;
  require Process::Status;
  require JSON::XS;

  my $plan_file = $args->[0];
  my $json = Path::Tiny::path($plan_file)->slurp;
  my $plan = JSON::XS->new->decode($json);

  my $boxman   = $self->boxman;
  my $droplet  = $boxman->_get_droplet_for($opt->username, "ci-run-$plan->{run_id}")->get;

  $droplet
    || die "Can't find the droplet to use! Did you run 'box ci-create'?\n";

  $ip = $boxman->_ip_address_for_droplet($droplet);

  my @cmd = (
    qw(
      scp
        -o UserKnownHostsFile=/dev/null
        -o StrictHostKeyChecking=no
        -o ControlMaster=no
    ),
    'misc/test-runner-on-vm',
    $plan_file,
    "root\@$ip:/tmp",
  );

  system @cmd;
  Process::Status->assert_ok("scping runner to target");

  my @taskstream_env = $opt->taskstream
                     ? qw( -o SetEnv=FM_TASKSTREAM=1 -o ControlMaster=No )
                     : ();

  my @ssh_cmd = (
    qw(
      ssh
        -o UserKnownHostsFile=/dev/null
        -o StrictHostKeyChecking=no
        -o SendEnv=FM_*
    ),
    @taskstream_env,
    "root\@$ip",
    "/tmp/test-runner-on-vm",
    "/tmp/$plan_file",
  );

  my $cb = $opt->taskstream
    ? Dobby::Boxmate::TaskStream->new_taskstream_cb({ loop => $boxman->dobby->loop })
    : sub ($line, @) { print $line if defined $line };

  my ($exitcode) = $boxman->_run_process_streaming(\@ssh_cmd, $cb)->get;

  $cb->(undef, $exitcode == 0 ? 1 : 0);

  exit($exitcode >> 8) if $exitcode;
}

1;
