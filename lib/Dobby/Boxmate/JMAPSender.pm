package Dobby::Boxmate::JMAPSender;
use Moose;

# ABSTRACT: send a simple email by JMAP

use v5.36.0;
use utf8;

use Future::AsyncAwait;
use JSON::XS ();
use Net::Async::HTTP;

=head1 OVERVIEW

This is just enough of a JMAP client to send one message: it creates the
message as a draft, submits it, and has the server destroy the draft once it's
been sent.  The sending identity must already exist on the account.

  my $sender = Dobby::Boxmate::JMAPSender->new({
    loop  => $loop,
    token => $api_token,
  });

  await $sender->send_email({
    from    => { name => 'Synergy', email => 'synergy@fastmailsystem.com' },
    to      => [ { name => 'Someone', email => 'someone@example.com' } ],
    cc      => [ ... ],     # optional
    subject => 'Hello',
    text    => "plain text body",
    html    => "<p>HTML body</p>",
  });

=cut

has loop => (
  is       => 'ro',
  required => 1,
);

has token => (
  is       => 'ro',
  required => 1,
);

has session_url => (
  is      => 'ro',
  default => 'https://api.fastmail.com/jmap/session',
);

has _http => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  default  => sub ($self) {
    my $http = Net::Async::HTTP->new(user_agent => 'Dobby/0');
    $self->loop->add($http);
    return $http;
  },
);

my $JSON = JSON::XS->new->utf8->canonical;

my @USING = qw(
  urn:ietf:params:jmap:core
  urn:ietf:params:jmap:mail
  urn:ietf:params:jmap:submission
);

async sub _request ($self, @arg) {
  my $res = await $self->_http->do_request(
    @arg,
    headers => { Authorization => "Bearer " . $self->token },
  );

  unless ($res->is_success) {
    die "JMAP request failed: " . $res->status_line . "\n";
  }

  return $JSON->decode($res->decoded_content(charset => undef));
}

async sub _session ($self) {
  return await $self->_request(method => 'GET', uri => $self->session_url);
}

# Make one API request, returning a hashref of call id to method arguments.
# Any method-level error is fatal.
async sub _call ($self, $session, $calls) {
  my $res = await $self->_request(
    method       => 'POST',
    uri          => $session->{apiUrl},
    content_type => 'application/json',
    content      => $JSON->encode({ using => \@USING, methodCalls => $calls }),
  );

  my %response;

  for my $sentence ($res->{methodResponses}->@*) {
    my ($name, $arg, $id) = @$sentence;

    if ($name eq 'error') {
      die "JMAP error in call $id: $arg->{type}"
        . (defined $arg->{description} ? " ($arg->{description})" : "")
        . "\n";
    }

    $response{$id} = $arg;
  }

  return \%response;
}

my sub _assert_created ($what, $set_response) {
  return unless my $not = $set_response->{notCreated};

  my @errors = map {; "$_->{type}" . (defined $_->{description} ? " ($_->{description})" : "") }
               values %$not;

  die "JMAP couldn't create $what: @errors\n";
}

async sub send_email ($self, $arg) {
  my $session    = await $self->_session;
  my $account_id = $session->{primaryAccounts}{'urn:ietf:params:jmap:submission'}
                // die "JMAP session has no submission account\n";

  my $setup = await $self->_call($session, [
    [ 'Identity/get',  { accountId => $account_id }, 'identities' ],
    [ 'Mailbox/query', {
        accountId => $account_id,
        filter    => { role => 'drafts' },
      }, 'drafts' ],
  ]);

  my $from_email = fc $arg->{from}{email};
  my ($identity) = grep {; fc $_->{email} eq $from_email } $setup->{identities}{list}->@*;

  $identity
    || die "JMAP account has no identity for $arg->{from}{email}\n";

  my ($drafts_id) = $setup->{drafts}{ids}->@*;

  $drafts_id
    || die "JMAP account has no Drafts mailbox\n";

  my $true = JSON::XS::true;

  my $sent = await $self->_call($session, [
    [ 'Email/set', {
        accountId => $account_id,
        create    => {
          draft => {
            mailboxIds => { $drafts_id => $true },
            keywords   => { '$draft' => $true, '$seen' => $true },
            from       => [ $arg->{from} ],
            to         => $arg->{to},
            ($arg->{cc} && $arg->{cc}->@* ? (cc => $arg->{cc}) : ()),
            subject    => $arg->{subject},
            textBody   => [ { partId => 'text', type => 'text/plain' } ],
            htmlBody   => [ { partId => 'html', type => 'text/html' } ],
            bodyValues => {
              text => { value => $arg->{text} },
              html => { value => $arg->{html} },
            },
          },
        },
      }, 'email' ],
    [ 'EmailSubmission/set', {
        accountId => $account_id,
        create    => {
          send => { emailId => '#draft', identityId => $identity->{id} },
        },
        onSuccessDestroyEmail => [ '#send' ],
      }, 'submission' ],
  ]);

  _assert_created("the email",      $sent->{email});
  _assert_created("the submission", $sent->{submission});

  return;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
