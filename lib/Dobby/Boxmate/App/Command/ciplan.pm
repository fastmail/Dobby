package Dobby::Boxmate::App::Command::ciplan;
use Dobby::Boxmate::App -command;

# ABSTRACT: write a CI plan file

use v5.36.0;
use utf8;

sub command_names {
  return qw(ci-plan ciplan);
}

sub opt_spec {
  return (
    [ 'run-id=s', 'CI run id, defaults to $CI_JOB_ID or a guid' ],
  );
}

sub _template_program {
  return [
    [ boot_up              => () ],
    [ start_early_services => () ],
    [ setup_cyrus          => () ],
    [ switch_to_branch     => 'fastmail/master' ],
    [ debian_upgrade       => () ],
    # [ conf_diff            => () ],
    [ conf_update          => () ],
    [ db_update            => () ],
    [ knot_update          => () ],
    [ cyrus_tmpfs          => () ],
    [ start_services       => () ],
    # [ newt_compile         => () ],
    [ newt_full            => () ],
    # [ cassandane           => () ],
    [ stop_services        => () ],
    [ log_gather           => () ],
  ];
}

sub execute ($self, $opt, $args) {
  require JSON::XS;
  require Path::Tiny;
  require Data::GUID; # for fallback run ids

  my $run_id = $opt->run_id
            // $ENV{CI_JOB_ID}
            // lc(Data::GUID->new->as_hex =~ s/^0x//r);

  my $ERR = q{❌};

  # For all the predefined variables, check out:
  # https://docs.gitlab.com/ci/variables/predefined_variables/
  for my $required (qw( DIGITAL_OCEAN_TOKEN )) {
    unless ($ENV{ $required }) {
      die "Can't initialize a CI run without the $required variable\n";
    }
  }

  # These are the defaults:
  my $size_preferences   = [ 'c-16', 'c-16-intel' ];
  my $region_preferences = [];

  my @labels = split q{,}, ($ENV{CI_MERGE_REQUEST_LABELS} // '');

  my $retain_droplet = (grep {; $_ eq 'dont-delete-testboxer' } @labels)
                     ? JSON::XS::true()
                     : JSON::XS::false();

  my (@regions) = map {; /\Atestboxer-region-(\S)+\z/ ? "$1" : () } @labels;
  if (@regions) {
    if (@regions > 1) {
      warn "$ERR More than one region label!  Going with $regions[0].\n";
    }

    $region_preferences = [ $regions[0] ];
  }

  my (@sizes) = map {; /\Atestboxer-size-(\S)+\z/ ? "$1" : () } @labels;
  if (@sizes) {
    if (@sizes > 1) {
      warn "$ERR More than one size label!  Going with $sizes[0].\n";
    }

    $size_preferences = [ $sizes[0] ];
  }

  # We don't put the Digital Ocean token into the plan because we assume that the
  # rest of the job is being run from the same environment.
  my $plan = {
    run_id => $run_id,
    size_preferences    => $size_preferences,
    region_preferences  => $region_preferences,
    retain_droplet      => $retain_droplet,
    program             => $self->_template_program,
  };

  # Probably we never have to read this by eye, but let's make it easy just in
  # case.
  Path::Tiny::path('ci-plan.json')->spew(
    JSON::XS->new->canonical->pretty->utf8->encode($plan)
  );
}

# FM_API_TOKEN: was used to run setup-hm-remotes
# $FM_API_TOKEN

# Sometimes used for running mint-tag
# $GITHUB_API_TOKEN
# $GITLAB_API_TOKEN

# Was used to send post-testing email reports
# $EMAIL_SENDER_TRANSPORT_sasl_password

# Sometimes set to pick what region/size default we want.
# $CI_DROPLET_REGION
# $CI_DROPLET_SIZE

# About picking the branch to test:  Given rjbs/hm, branch cool-feature:
#
# $CI_MERGE_REQUEST_SOURCE_PROJECT_PATH is "rjbs/hm"
# $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME  is "cool-feature"

### Was set up for Ansible, but never used?
# $CI_PIPELINE_SOURCE
#   https://docs.gitlab.com/ci/jobs/job_rules/#ci_pipeline_source-predefined-variable
#   Could be one of: api, merge_request_event, pipeline, schedule, or others

1;
