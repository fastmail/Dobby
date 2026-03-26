package Dobby::Boxmate::App::Command;
use parent 'App::Cmd::Command';

# ABSTRACT: the base class for box commands

use v5.36.0;
use experimental 'builtin';

sub boxman ($self) {
  $self->app->boxman;
}

sub maybe_droplet_from_prefix ($self, $boxprefix) {
  length $boxprefix
    || $self->usage->die({ pre_text => "No box prefix provided.\n\n" });

  my $boxman = $self->boxman;

  my $username = $self->app->config->username;
  my $droplets = $boxman->get_droplets_for($username)->get;

  my $want_name = join q{.}, $boxprefix, $username, $boxman->box_domain;
  my ($droplet) = grep {; $_->{name} eq $want_name } @$droplets;

  return $droplet;
}

sub droplet_from_prefix ($self, $boxprefix) {
  my $droplet = $self->maybe_droplet_from_prefix($boxprefix);

  unless ($droplet) {
    die "Couldn't find box for $boxprefix\n";
  }

  return $droplet;
}

sub print_droplet_list ($self, $droplets, $username = undef) {
  require DateTime::Format::RFC3339;
  require Term::ANSIColor;
  require Text::Table;
  require Time::Duration;

  my $parser = DateTime::Format::RFC3339->new;
  my $boxman = $self->boxman;

  # Ugh, should sort out the ME:: table formatter for general use.
  my $table = Text::Table->new(
    '', # Status
    'region',
    '  ', # Type
    '  ', # Default
    'name',
    'ip',
    { title => 'age', align => 'right' },
    { title => 'cost', align => 'right' },
    { title => 'img age', align => 'right', align_title => 'right' },
  );

  my $default;
  if ($username) {
    my ($rec) = grep {; $_->{type} eq 'CNAME' && $_->{name} eq $username }
                $boxman->dobby->get_all_domain_records_for_domain($boxman->box_domain)->get;

    $default = $rec->{data};
  }

  for my $droplet (@$droplets) {
    my $name   = $droplet->{name};
    my $status = $droplet->{status};
    my $ip     = $boxman->_ip_address_for_droplet($droplet); # XXX _method
    my $image  = $droplet->{image};

    my $created  = $parser->parse_datetime($droplet->{created_at});
    my $age_secs = time - $created->epoch;

    my $img_created  = $parser->parse_datetime($image->{created_at});
    my $img_age_secs = time - $img_created->epoch;

    my $cost = sprintf '%4s',
      '$' .  builtin::ceil($droplet->{size}{price_hourly} * $age_secs / 3600);

    my $icon = ($image->{slug} && $image->{slug} =~ /^debian/)  ? "\N{CYCLONE}"
             : (($image->{description}//'') =~ /^Debian/)       ? "\N{CYCLONE}" # Deb 11
             : ($image->{slug} && $image->{slug} =~ /^docker-/) ? "\N{SHIP}"
             : ($image->{name} =~ /\Afminabox/)                 ? "\N{PACKAGE}"
             :                                                    "\N{BLACK QUESTION MARK ORNAMENT}";

    my $default = $default && $default eq $name
                ? "\N{SPARKLES}"
                : "\N{IDEOGRAPHIC SPACE}";

    $table->add(
      ($status eq 'active' ? "\N{LARGE GREEN CIRCLE}" : "\N{HEAVY MINUS SIGN}"),
      $droplet->{region}{slug},
      "$icon\N{INVISIBLE SEPARATOR}",
      "$default\N{INVISIBLE SEPARATOR}",
      $name,
      $ip,
      Time::Duration::concise(Time::Duration::duration($age_secs, 1)),
      $cost,
      Time::Duration::concise(Time::Duration::duration($img_age_secs, 1)),
    );
  }

  # This leading space is *bananas* and is here because Text::Table will think
  # about LARGE GREEN CIRCLE as being one wide, but it's two.
  print Term::ANSIColor::colored(['bold', 'bright_white'], qq{ $_}) for $table->title;
  print qq{$_}  for $table->body;
}

1;
