package Dobby::Boxmate::Config;
use Moose;

use v5.36.0;

use Defined::KV qw(defined_kv);
use Path::Tiny ();

# Dobby::BoxManager config:
has box_domain => (is => 'ro', isa => 'Str', default => 'fastmailvm.com');
has ssh_key_id => (is => 'ro', isa => 'Str', predicate => 'has_ssh_key_id');
has digitalocean_ssh_key_name => (is  => 'ro', isa => 'Str', required => 1);

# ProvisioningSpec config:
has region      => (is => 'ro', isa => 'Str', default => 'nyc3');
has size        => (is => 'ro', isa => 'Str', default => 'g-4vcpu-16gb');
has username    => (is => 'ro', isa => 'Str', default => $ENV{USER});
has version     => (is => 'ro', isa => 'Str', default => 'bookworm');

has project_id  => (
  is  => 'ro',
  isa => 'Str',
  default => 'd733cd68-8069-4815-ad49-e557a870ac0a',
);

has run_custom_setup => (is => 'ro', isa => 'Bool', default => 1);
has setup_switches   => (
  is  => 'ro',
  isa => 'ArrayRef',
  default => sub {  []  },
);

sub load ($class) {
  my $config_file = Path::Tiny::path("~/.boxmate.toml");

  my %override;

  if (-e $config_file) {
    require Carp;
    require JSON::MaybeXS;
    require TOML::Parser;

    my $parser = TOML::Parser->new(
      inflate_boolean  => sub {
          $_[0] eq 'true'   ? JSON::MaybeXS::true()
        : $_[0] eq 'false'  ? JSON::MaybeXS::false()
        : Carp::confess("Unexpected value passed to inflate_boolean: $_[0]")
      }
    );

    # XXX This is pretty bogus but I just want to get this stuff done.
    my $data = $parser->parse($config_file->slurp_utf8);
    %override = (
      ($data->{boxman} ? $data->{boxman}->%* : ()),
      ($data->{create} ? $data->{create}->%* : ()),
    );
  }

  unless ($override{digitalocean_ssh_key_name}) {
    die "~/.boxmate.toml doesn't contain digitalocean_ssh_key_name\n";
  }

  return $class->new(\%override);
}

1;
