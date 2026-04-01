package Dobby::Boxmate::App::Command::cidestroy;
use Dobby::Boxmate::App -command;

# ABSTRACT: destroy a box

use v5.36.0;
use utf8;

use Dobby::GitLabUtil '-all';

sub command_names {
  return qw(ci-destroy cidestroy);
}

sub abstract { 'destroy a CI box' }

sub opt_spec {
  return (
    [ 'username=s', "put the box in this user's namespace", { default => $ENV{USER} }, ],
    [ 'force',      "destroy even if the plan says not to" ],
  );
}

sub usage_desc {
  '%c destroy %o [PLANFILE]',
}

sub validate_args ($self, $opt, $args) {
  @$args <= 1 || $self->usage->die;

  my $plan_file = $args->[0] // $self->app->_default_plan_filename;
  -r $plan_file || die "Can't read plan file $plan_file!\n";

  $opt->username
    || $self->usage->die({ pre_text => "Neither --username nor \$USER was supplied.\n\n" });
}

sub execute ($self, $opt, $args) {
  require Process::Status;

  my $plan_file = $args->[0] // $self->app->_default_plan_filename;
  my $plan = $self->app->_read_plan_file($plan_file);

  if ($plan->{retain_droplet} && ! $opt->force) {
    say "Won't destroy box without --force, the plan says to keep it.";
    exit;
  }

  my $boxman   = $self->boxman;
  my $droplet  = $boxman->_get_droplet_for($opt->username, "ci-run-$plan->{run_id}")->get;

  unless ($droplet) {
    die "I couldn't find the box you want to destroy.\n";
  }

  start_section('destroying-droplet', 'Destroying Droplet');

  $boxman->destroy_droplet($droplet, { force => 1 })->get;

  end_section('destroying-droplet');
}

1;
