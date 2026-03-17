package Dobby::TestClient;
use v5.36.0;

# A subclass of Dobby::Client suitable for unit tests.  It replaces
# Net::Async::HTTP with Test::Async::HTTP and routes requests to per-path
# handler coderefs registered by the test, so no real network access occurs.

use parent 'Dobby::Client';

use Carp ();
use HTTP::Response;
use JSON::XS;
use Test::Async::HTTP;

# Test::Async::HTTP isn't an IO::Async::Notifier, so it doesn't need to be
# added to the loop.
sub _http ($self) {
  return $self->{__test_http} //= Test::Async::HTTP->new;
}

# The path is relative to /v2, without respect to query strings.
#
# The handler is called with a HTTP::Request and must return an HTTP::Response.
sub register_url_handler ($self, $path, $handler) {
  $self->{__test_url_handlers}{$path} = $handler;
}

# Convenience: register a handler that always responds with $data encoded as
# JSON with a 200 status.
sub register_url_json ($self, $path, $data) {
  $self->register_url_handler($path, sub ($req) {
    my $res = HTTP::Response->new(200, 'OK');
    $res->header('Content-Type' => 'application/json');
    $res->content(encode_json($data));
    return $res;
  });
}

sub _do_request ($self, %args) {
  # Test::Async::HTTP doesn't handle headers or content_type; strip them
  # before passing through (we never need to inspect auth headers in tests).
  delete @args{qw(headers content_type)};

  my $f = $self->_http->do_request(%args);

  my $base = $self->api_base;
  (my $path = $args{uri}) =~ s{\A\Q$base\E}{};
  $path =~ s{\?.*\z}{};

  my $handler = $self->{__test_url_handlers}{$path}
    or Carp::confess("Dobby::TestClient: no handler registered for $path");

  my $pending = $self->_http->next_pending;
  $pending->respond($handler->($pending->request));

  return $f;
}

1;
