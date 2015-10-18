
use v6;

=begin pod
=end pod
unit class Selenium::WebDriver;

use HTTP::UserAgent;
use JSON::Tiny;
use MIME::Base64;

has Bool        $.debug is rw;
has Int         $.port is rw;
has Str         $.session_id is rw;
has Proc::Async $.process is rw;

=begin pod
=end pod
submethod BUILD( Int :$port = 5555, Bool :$debug = False ) {
  self.debug   = $debug;
  self.port    = $port;
  self.process = self.new_phantomjs_process;

  # Try to create a new phantomjs session for n times
  my constant MAX_ATTEMPTS = 3;
  my $session;
  for 1..MAX_ATTEMPTS {
    # Try to create session
    $session = self.new_session;
    last if $session.defined;

    CATCH {
      default {
        # Retry session creation failure after timeout
        say "Attempt $_ to create session" if self.debug;
        sleep 1;
      }
    }
  }

  # No session could be created
  die "Cannot obtain a session after $(MAX_ATTEMPTS) attempts" unless $session.defined;

  self.session_id = $session<sessionId>;
  die "Session id is not defined" unless self.session_id.defined;
}

=begin pod
=end pod
method new_phantomjs_process {
  say "Starting phantomjs process" if $.debug;
  my $process = Proc::Async.new(
    'phantomjs',
    "--webdriver=" ~ $.port,
    "--webdriver-loglevel=WARN"
  );
  $process.start;

  return $process;
}

=begin pod
=end pod
# POST /session
method new_session {
  return self._execute_command(
    "POST",
    "/session",
    {
        "desiredCapabilities"  => {},
        "requiredCapabilities" => {},
    }
  );
}

=begin pod
=end pod
# POST /session/:sessionId/url
method set_url(Str $url) {
  return self._execute_command(
    "POST",
    "/session/$(self.session_id)/url",
    {
        url => $url,
    }
  );
}

=begin pod
=end pod
# GET /session/:sessionId/url
method get_url {
  return self._execute_get( 'url' );
}

=begin pod
=end pod
# GET /session/:sessionId/title
method get_title {
  return self._execute_get( 'title' );
}

=begin pod
=end pod
# GET /session/:sessionId/source
method get_source {
  return self._execute_get( 'source' );
}

=begin pod
=end pod
# POST /session/:sessionId/moveto
method move_to(Str $element, Int $xoffset, Int $yoffset) {
  return self._execute_command(
    "POST",
    "/session/$(self.session_id)/moveto",
    {
        element => $element,
        xoffset => $xoffset,
        yoffset => $yoffset,
    }
  );
}

=begin pod
=end pod
# POST /session/:sessionId/click
method click {
  return self._execute_command(
    "POST",
    "/session/$(self.session_id)/click",
  );
}

=begin pod
=end pod
method quit {
  #TODO kill session
  $.process.kill if $.process.defined;
};

=begin pod
=end pod
# GET /session/:sessionId/screenshot
method get_screenshot() {
  return self._execute_get('screenshot');
}

=begin pod
=end pod
method save_screenshot(Str $filename) {
  my $result = self.get_screenshot();
  $filename.IO.spurt(MIME::Base64.decode( $result ));
}

=begin pod
=end pod
method _execute_command(Str $method, Str $command, Hash $params = {}) {
  say "POST $command with params " ~ $params.perl if self.debug;

  my $ua = HTTP::UserAgent.new;
  $ua.timeout = 5;
  my $url = "http://127.0.0.1:" ~ self.port ~ $command;
  my $response;
  if ( $method eq "POST" ) {
      my $content = to-json($params);
      my $request = HTTP::Request.new(
        :POST($url),
        :Content-Length($content.chars),
        :Content-Type("application/json;charset=UTF-8"),
        :Connection("close"),
      );
      $request.add-content($content);
      $response = $ua.request($request);
  }
  elsif ( $method eq "GET" ) {
    $response = $ua.get( $url );
  }
  else {
    die qq{Unknown method "$method"};
  }

  my $result;
  if ( $response.is-success ) {
      $result = from-json( $response.content );
  }
  else {
      warn "FAILED: " ~ $response.status-line if self.debug;
  }

  return $result;
}

method _execute_get(Str $command) {
  my $result = self._execute_command(
    "GET",
    "/session/$(self.session_id)/$command",
  );

  die "/$command returned an undefined response" unless $result.defined;
  return $result<value>;
}
