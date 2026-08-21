#!perl
# The client path: `DEF.client`, client-scoped options, and `contextify`.
#
# This port had no such test. Every migrated port runs this group
# (javascript/test/client.test.js, php/tests/ClientTest.php,
# lua/test/client_test.lua, csharp/tests/ClientTest.cs,
# java/src/test/ClientTest.java), and it is the only thing that exercises
# subject resolution through a PROVIDER rather than through a callback the
# test file hands over - so nothing here had ever checked that a corpus
# `client` key resolves, or that a `DEF.client` entry's options reach the
# subject.
#
# Two entries, differing only in which client answers: the default one with no
# options gives "ZED_BAR0", and client "a" - carrying `{foo: 1}` - gives
# "ZED1_BAR1".
#
# The subject here talks to omni DIRECTLY (plain hashes, no sentinels), because
# the runner resolves it by name off the provider: there is no `in` to convert
# and no result for OmniBridge to convert back.

use 5.018;
use strict;
use warnings;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin";

use Voxgig::Struct qw();

use OmniBridge;

my $corpus = "$FindBin::Bin/../../build/test/test.json";
plan skip_all => "Corpus file not found: $corpus" unless -e $corpus;

# The SDK's `check` subject. `$opts` is what a `DEF.client` entry carried,
# `$ctx` is the entry's own context.
sub check {
    my ( $opts, $ctx ) = @_;

    my $foo = ref $opts eq 'HASH' ? $opts->{foo} : undef;
    my $foos = defined $foo ? Voxgig::Struct::stringify($foo) : '';

    my $bars = '0';
    if ( ref $ctx eq 'HASH' && ref $ctx->{meta} eq 'HASH' ) {
        my $bar = $ctx->{meta}{bar};
        $bars = Voxgig::Struct::stringify($bar) if defined $bar;
    }

    return { zed => 'ZED' . $foos . '_' . $bars };
}

# A provider carrying one client's options.
sub provider {
    my ($options) = @_;

    my $self;
    $self = {
        subject => sub {
            my ($name) = @_;
            return if 'check' ne $name;
            return sub { return check( $options, $_[0] ) };
        },

        # A DEF.client entry becomes another provider, carrying its options.
        client => \&provider,

        # This port adds nothing to a context; the hook must exist so omni
        # installs `client` on it.
        contextify => sub { return $_[0] },
    };

    return $self;
}

my $run = OmniBridge::make_run( 'check', provider( {} ) );

# No subject: the runner resolves it by name off the provider, which is the
# whole point of the group.
my $ok = eval { $run->{runsetnamed}->( $run->{spec}{basic}, {} ); 1 };
if ($ok) { pass('client-check-basic') }
else {
    fail('client-check-basic');
    diag("client-check-basic: $@");
}

done_testing();
