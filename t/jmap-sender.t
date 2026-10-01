use v5.36.0;
use utf8;

use Future::AsyncAwait;
use IO::Async::Loop;
use JSON::XS ();
use Test::More;
use Test::Deep ':v1';

package TestSender {
  use Moose;
  extends 'Dobby::Boxmate::JMAPSender';

  use v5.36.0;
  use Future::AsyncAwait;

  # The fake server: identities, draft mailbox ids, and optionally a method
  # name that should produce an error or a set that should fail.
  has server => (is => 'ro', required => 1);

  # Every method call made, as [ name, args ], in order.
  has calls  => (is => 'ro', default => sub { [] });

  my $JSON = JSON::XS->new->utf8;

  my %handler = (
    'Identity/get'  => sub ($server, $arg) { { list => $server->{identities} } },
    'Mailbox/query' => sub ($server, $arg) { { ids  => $server->{drafts} } },

    'Email/set' => sub ($server, $arg) {
      return { notCreated => $server->{not_created}{email} } if $server->{not_created}{email};
      return { created => { draft => { id => 'E1' } } };
    },

    'EmailSubmission/set' => sub ($server, $arg) {
      return { notCreated => $server->{not_created}{submission} } if $server->{not_created}{submission};
      return { created => { send => { id => 'S1' } } };
    },
  );

  async sub _request ($self, %arg) {
    if ($arg{method} eq 'GET') {
      return {
        apiUrl          => 'https://jmap.example.com/api/',
        primaryAccounts => { 'urn:ietf:params:jmap:submission' => 'A1' },
      };
    }

    my $req = $JSON->decode($arg{content});
    my @responses;

    for my $call ($req->{methodCalls}->@*) {
      my ($name, $args, $id) = @$call;
      push $self->calls->@*, [ $name, $args ];

      if (($self->server->{error_for} // '') eq $name) {
        push @responses, [ 'error', { type => 'serverFail' }, $id ];
        next;
      }

      push @responses, [ $name, $handler{$name}->($self->server, $args), $id ];
    }

    return { methodResponses => \@responses };
  }

  no Moose;
}

my %server = (
  identities => [
    { id => 'I1', email => 'someone-else@fastmailsystem.com' },
    { id => 'I2', email => 'Synergy@FastmailSystem.com' },
  ],
  drafts     => [ 'M7' ],
);

my %message = (
  from    => { name => 'Synergy', email => 'synergy@fastmailsystem.com' },
  to      => [ { email => 'archive@example.com' } ],
  subject => 'Test Report',
  text    => "All is well.\n",
  html    => "<p>All is well.</p>\n",
);

my $loop = IO::Async::Loop->new;

my sub attempt_send ($server, $message) {
  my $sender = TestSender->new({ loop => $loop, token => 'T', server => $server });
  my $ok     = eval { $sender->send_email($message)->get; 1 };

  return ($ok ? undef : $@, { map {; $_->[0] => $_->[1] } $sender->calls->@* });
}

sub send_ok ($desc, $server, $message, $expect) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($error, $calls) = attempt_send($server, $message);

  subtest $desc => sub {
    is($error, undef, "no error");

    cmp_deeply(
      $calls->{'Email/set'}{create}{draft},
      superhashof($expect->{email}),
      "the right email was created",
    );

    cmp_deeply(
      $calls->{'EmailSubmission/set'},
      superhashof({
        create => { send => { emailId => '#draft', identityId => $expect->{identity_id} } },
        onSuccessDestroyEmail => [ '#send' ],
      }),
      "it was submitted from the right identity, and the draft destroyed",
    );
  };
}

sub send_fails_ok ($desc, $server, $message, $error_re) {
  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my ($error) = attempt_send($server, $message);
  like($error, $error_re, $desc);
}

send_ok(
  "a plain send, matching identity email case-insensitively",
  \%server,
  \%message,
  {
    identity_id => 'I2',
    email => {
      mailboxIds => { M7 => JSON::XS::true },
      from       => [ $message{from} ],
      to         => $message{to},
      subject    => 'Test Report',
      bodyValues => {
        text => { value => $message{text} },
        html => { value => $message{html} },
      },
    },
  },
);

send_ok(
  "cc recipients are included when given",
  \%server,
  { %message, cc => [ { email => 'plumbing@example.com' } ] },
  { identity_id => 'I2', email => { cc => [ { email => 'plumbing@example.com' } ] } },
);

{
  my ($error, $calls) = attempt_send(\%server, { %message, cc => [] });
  ok(! exists $calls->{'Email/set'}{create}{draft}{cc}, "an empty cc list is left out");
}

send_fails_ok(
  "no identity for the From address",
  { %server, identities => [ { id => 'I1', email => 'nope@example.com' } ] },
  \%message,
  qr/no identity for synergy\@fastmailsystem\.com/,
);

send_fails_ok(
  "no drafts mailbox",
  { %server, drafts => [] },
  \%message,
  qr/no Drafts mailbox/,
);

send_fails_ok(
  "a method-level error",
  { %server, error_for => 'Identity/get' },
  \%message,
  qr/JMAP error in call identities: serverFail/,
);

send_fails_ok(
  "the email couldn't be created",
  { %server, not_created => { email => { draft => { type => 'invalidProperties', description => 'bad to' } } } },
  \%message,
  qr/couldn't create the email: invalidProperties \(bad to\)/,
);

send_fails_ok(
  "the submission couldn't be created",
  { %server, not_created => { submission => { send => { type => 'forbiddenFrom' } } } },
  \%message,
  qr/couldn't create the submission: forbiddenFrom/,
);

done_testing;
