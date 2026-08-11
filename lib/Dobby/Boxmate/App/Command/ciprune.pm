package Dobby::Boxmate::App::Command::ciprune;
use Dobby::Boxmate::App -command;

# ABSTRACT: destroy CI boxes that have outlived their usefulness

use v5.36.0;
use utf8;

use Dobby::GitLabUtil '-all';

sub command_names {
  return qw(ci-prune ciprune);
}

sub abstract { 'destroy leftover CI boxes' }

sub usage_desc { '%c ci-prune %o' }

sub opt_spec {
  return (
    [ 'max-age=i', 'destroy CI boxes older than this many hours', { default => 6 } ],
    [ 'dry-run|n', "don't destroy anything, just report what would be destroyed" ],
  );
}

sub validate_args ($self, $opt, $args) {
  @$args == 0 || $self->usage->die;

  $opt->max_age > 0
    || $self->usage->die({ pre_text => "--max-age must be a positive number of hours.\n\n" });
}

# Args:
#   - droplets: an arrayref of droplet data
#   - now     : time in epoch sec
#   - max_age : seconds past which a box is disposable
# Returns a list:
#   - [ all ci boxes ]
#   - [ ci boxes > max age ]
sub sort_boxes_to_prune ($self, $arg) {
  require DateTime::Format::RFC3339;

  my $parser = DateTime::Format::RFC3339->new;
  my $now    = $arg->{now};

  my @ci_boxes = sort {; $b->{age} <=> $a->{age} }
                 map  {; {
                   droplet => $_,
                   age     => $now - $parser->parse_datetime($_->{created_at})->epoch,
                 } }
                 grep {; $_->{name} =~ m{\Aci-run-} }
                 $arg->{droplets}->@*;

  my @doomed = grep {; $_->{age} > $arg->{max_age} } @ci_boxes;

  return (\@ci_boxes, \@doomed);
}

sub execute ($self, $opt, $args) {
  require Time::Duration;

  my $boxman  = $self->boxman;
  my $max_age = $opt->max_age * 3600;

  my @droplets = $boxman->dobby->get_all_droplets->get;

  my ($ci_boxes, $doomed) = $self->sort_boxes_to_prune({
    droplets => \@droplets,
    now      => time,
    max_age  => $max_age,
  });

  say sprintf 'Found %s CI box%s, %s of them older than %s.',
    0+@$ci_boxes, (@$ci_boxes == 1 ? q{} : 'es'),
    0+@$doomed,
    Time::Duration::duration($max_age);

  my @failures;

  for my $box (@$doomed) {
    my $droplet = $box->{droplet};

    my $desc = sprintf '%s (age %s)',
      $droplet->{name},
      Time::Duration::concise(Time::Duration::duration($box->{age}, 2));

    if ($opt->dry_run) {
      say "🔹 Would destroy $desc";
      next;
    }

    my $ident = "pruning-$droplet->{id}";
    start_section($ident, "Destroying $desc");

    # one indestructible box shouldn't keep us from pruning the rest of them
    my $ok = eval { $boxman->destroy_droplet($droplet, { force => 1 })->get; 1 };

    unless ($ok) {
      my $error = $@ || "unknown error";
      $error =~ s{\s+\Z}{};

      push @failures, $droplet->{name};
      say "Couldn't destroy $droplet->{name}: $error";
    }

    end_section($ident);
  }

  if (@failures) {
    die sprintf "Failed to destroy %s box%s: %s\n",
      0+@failures, (@failures == 1 ? q{} : 'es'), (join q{, }, @failures);
  }
}

1;
