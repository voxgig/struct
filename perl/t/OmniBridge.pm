package OmniBridge;

# The shared test runner comes from voxgig/omni, consumed as a local checkout
# - omni is deliberately not published to CPAN (yet). The checkout is resolved
# the same way voxgig/sekreto's ports resolve it: $OMNI_HOME first, then
# sibling paths, taking the first directory that carries spec/fib.json.
#
# Only the tests depend on omni. The library never does, and Makefile.PL gains
# no prerequisite - this pushes a directory onto @INC at run time, so anything
# built or installed from lib/ is untouched (register 4.13).
#
# This is the Perl counterpart of python/tests/omni.py, php/tests/omni.php,
# lua/test/omni.lua, csharp/tests/Omni.cs and java/src/test/Omni.java.
#
# ---------------------------------------------------------------------------
# Two value models, four differences
# ---------------------------------------------------------------------------
#
# This is the widest gap any port has had, because both sides model JSON with
# their own sentinels and they disagree on all of them:
#
#     concept    omni                      struct/perl
#     -------    ----                      -----------
#     absent     Voxgig::Omni::Absent      Voxgig::Struct::None
#     null       undef                     Voxgig::Struct::Null
#     boolean    JSON::PP::Boolean         Voxgig::Struct::Bool
#     map        plain HASH                tied, insertion-ordered HASH
#
# The first three are converted, both ways, by `tostruct` and `toomni`. The
# fourth is not - and does not need to be, see below.
#
# Note that this port does NOT have lua's or php's problem: `undef` and
# "no value" are different things here, so nothing is guessed. A JSON null
# in the corpus arrives as omni's undef and becomes JNULL; a subject that
# answers "nothing" answers NONE and becomes ABSENT. Only a BARE undef -
# a subject returning plain `return;` - is ambiguous, and it reads as absent
# because that is what a Perl sub returning nothing means.
#
# ---------------------------------------------------------------------------
# `tostruct` converts IN PLACE
# ---------------------------------------------------------------------------
#
# It rewrites omni's own containers rather than copying them, so the subject
# receives the very hash omni put in the argument list. That is what makes
# `match.args` work: `minor/setpath` asserts the store AFTER an in-place
# rewrite in eight of its nine entries, and `merge/integrity` in all six.
# Copying would leave omni holding the unmutated original, which is why go and
# csharp had to write mutated arguments back by hand and rust needed a mutable
# -argument subject added to the runner.
#
# It is safe: `resolveargs` clones `entry->{in}` before handing it over, so the
# hash being rewritten is already the entry's own copy, not the loaded spec.
#
# `toomni` copies instead, because a value coming back was built by the port
# and rewriting it could disturb a container the port still holds.
#
# ---------------------------------------------------------------------------
# Map key order
# ---------------------------------------------------------------------------
#
# omni-perl decodes the spec with JSON::PP, so its maps are plain hashes and
# JSON member order is gone - and omni's own `jsonstr` sorts map keys, so the
# runner treats that order as insignificant throughout. This port agrees:
# `keysof` sorts, `deepequal` ignores order, and `_map_keys` now sorts an
# untied hash rather than returning it in Perl's randomised order. `jsonify`
# is the one place order is observable, and the corpus writes every jsonify
# map in sorted key order precisely so that a port without insertion order can
# still answer it - which is also how struct/go passes, via `json.Marshal`.

use strict;
use warnings;

use File::Spec;
use JSON::PP ();

our ( $ABSENT, $NULLMARK, $UNDEFMARK, $EXISTSMARK );

# omni spells JSON null `undef`. Named, because returning a bare `undef` from
# `toomni` would be a `return undef` - which perlcritic rejects - and a bare
# `return` would be worse: `toomni` is called from inside a `map`, and there
# an empty return silently drops the element instead of yielding a null.
our $OMNINULL = undef;

# Locate the checkout and put omni on @INC before anything tries to use it.
BEGIN {
    my @candidates;
    push @candidates, $ENV{OMNI_HOME} if defined $ENV{OMNI_HOME} && length $ENV{OMNI_HOME};
    push @candidates, '../../omni', '../../../omni', '/workspace/omni', '/home/user/omni';

    my $home;
    for my $candidate (@candidates) {
        if ( -f File::Spec->catfile( $candidate, 'spec', 'fib.json' ) ) {
            $home = $candidate;
            last;
        }
    }
    die "struct: voxgig/omni checkout not found - set OMNI_HOME\n" if !defined $home;

    unshift @INC, File::Spec->catdir( $home, 'perl', 'lib' );
    $OmniBridge::HOME = $home;
}

use Voxgig::Omni::Runner qw(makeRunner);
use Voxgig::Omni::Util qw(ABSENT NULLMARK UNDEFMARK EXISTSMARK isabsent ismap islist);

use Voxgig::Struct qw();

BEGIN {
    $ABSENT     = ABSENT();
    $NULLMARK   = NULLMARK();
    $UNDEFMARK  = UNDEFMARK();
    $EXISTSMARK = EXISTSMARK();
}

# The shared corpus, relative to the port directory as the tests run.
sub corpus_path { return File::Spec->catfile( '..', 'build', 'test', 'test.json' ) }

# omni's model -> this port's, rewriting containers in place. See the header.
sub tostruct {
    my ($val) = @_;

    return Voxgig::Struct::NONE()  if isabsent($val);
    return Voxgig::Struct::JNULL() if !defined $val;
    return ( $val ? Voxgig::Struct::JTRUE() : Voxgig::Struct::JFALSE() )
      if JSON::PP::is_bool($val);

    if ( ismap($val) ) {
        for my $key ( keys %$val ) {
            $val->{$key} = tostruct( $val->{$key} );
        }
        return $val;
    }

    if ( islist($val) ) {
        for my $index ( 0 .. $#$val ) {
            $val->[$index] = tostruct( $val->[$index] );
        }
        return $val;
    }

    return $val;
}

# This port's model -> omni's, as a copy. A bare undef reads as absent: a Perl
# sub that returns nothing returns undef, and this port spells a JSON null
# JNULL, so undef here is never "null".
sub toomni {
    my ($val) = @_;

    return $ABSENT   if !defined $val || Voxgig::Struct::is_none($val);
    return $OMNINULL if Voxgig::Struct::is_jnull($val);
    return ( $$val ? JSON::PP::true : JSON::PP::false )
      if Voxgig::Struct::is_jbool($val);

    if ( ismap($val) ) {
        my %out;
        for my $key ( Voxgig::Struct::_map_keys($val) ) {
            $out{$key} = toomni( $val->{$key} );
        }
        return \%out;
    }

    if ( islist($val) ) {
        return [ map { toomni($_) } @$val ];
    }

    return $val;
}

# struct's runner API, backed by omni. `$provider` is optional; only the client
# group needs one.
sub make_run {
    my ( $name, $provider ) = @_;

    my $runner  = makeRunner( corpus_path(), $provider || {} );
    my $runpack = $runner->($name);

    my $runsetflags = sub {
        my ( $testspec, $flags, $subject ) = @_;

        my $wrapped = !defined $subject ? undef : sub {
            my (@args) = @_;
            my $in = tostruct( @args ? $args[0] : $ABSENT );
            return toomni( $subject->($in) );
        };

        return $runpack->{runsetflags}->( $testspec, $flags || {}, $wrapped );
    };

    return {
        spec => $runpack->{spec},

        # Run one group with omni's default flags.
        runset => sub {
            my ( $testspec, $subject ) = @_;
            return $runsetflags->( $testspec, {}, $subject );
        },

        # Run one group with an explicit `null` flag.
        runsetnull => sub {
            my ( $testspec, $donull, $subject ) = @_;
            return $runsetflags->( $testspec, { null => $donull }, $subject );
        },

        # Run one group with explicit flags.
        runsetflags => $runsetflags,

        # Run one group against the subject the SPEC names, through the
        # provider. This is the client path - `DEF.client`, and an entry's own
        # `client` key.
        runsetnamed => sub {
            my ( $testspec, $flags ) = @_;
            return $runpack->{runsetflags}->( $testspec, $flags || {}, undef );
        },
    };
}

1;
