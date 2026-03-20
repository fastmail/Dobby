package Dobby::Boxmate::App::Command::cidestroy;
use Dobby::Boxmate::App -command;

# ABSTRACT: destroy a box

use v5.36.0;
use utf8;

sub command_names {
  return qw(ci-destroy cidestroy);
}

sub abstract { 'destroy a CI box' }

sub opt_spec {
  return (
    [ 'username=s',   "put the box in this user's namespace", { default => $ENV{USER} }, ],
  );
}

sub usage_desc {
  '%c destroy %o [PLANFILE]',
}

sub validate_args ($self, $opt, $args) {
  @$args <= 1 || $self->usage->die;

  my $plan_file = $args->[0] // $self->app->_default_plan_file;
  -r $plan_file || die "Can't read plan file $plan_file!\n";

  $opt->username
    || $self->usage->die({ pre_text => "Neither --username nor \$USER was supplied.\n\n" });
}

sub execute ($self, $opt, $args) {
  require Process::Status;

  my $plan_file = $args->[0] // $self->app->_default_plan_file;
  my $plan = $self->app->_read_plan_file($plan_file);

  my $boxman   = $self->boxman;
  my $droplet  = $boxman->_get_droplet_for($opt->username, "ci-run-$plan->{run_id}")->get;

  unless ($droplet) {
    die "I couldn't find the box you want to destroy.\n";
  }

  my $time = time;
  say "\e[0Ksection_start:$time:destroying-droplet[collapsed=true]\r\e[0KDestroying Droplet";

  $boxman->destroy_droplet($droplet, { force => 1 })->get;

  $time = time;
  say "\e[0Ksection_end:$time:destroying-droplet\r\e[0K";
}

1;
