package Dobby::Boxmate::App::Command::list;
use Dobby::Boxmate::App -command;

# ABSTRACT: list your boxes

use v5.36.0;
use utf8;

use experimental 'builtin';

sub abstract { "list your boxes" }

sub opt_spec {
  return (
    [ 'username|u=s',  'boxes for some other user' ],
    [ 'everything',    'get every single droplet' ],
    [ 'name=s',        'only the named box' ],
    [],
    [ 'with-tag|T=s@', 'only boxes with this tag' ],
  );
}

sub validate_args ($self, $opt, $args) {
  my @exclusives;
  push @exclusives, grep {; $opt->$_ } qw(username everything name);

  if (@exclusives > 1) {
    die "These options are mutually exclusive: "
      . (join q{, }, map {; "--$_" } @exclusives)
      . "\n";
  }
}

sub execute ($self, $opt, $args) {
  my $config = $self->app->config;
  my $boxman = $self->boxman;

  my $username = $opt->username // $config->username;

  my $droplets;
  if ($opt->everything) {
    my @droplets = $boxman->dobby->get_all_droplets->get;
    @droplets = grep {; $_->{name} eq $opt->name } @droplets if $opt->name;
    $droplets = \@droplets;
  } else {
    $droplets = $boxman->get_droplets_for($username)->get;
  }

  if ($opt->with_tag) {
    my %want_tag = map {; $_ => 1 } $opt->with_tag->@*;

    @$droplets = grep {; my @tags = ($_->{tags} // [])->@*;
                         grep {; $want_tag{$_} } @tags } @$droplets;
  }

  unless (@$droplets) {
    say "📦 No boxes.";
    return;
  }

  $self->print_droplet_list($droplets, $username);
  return;
}

1;
