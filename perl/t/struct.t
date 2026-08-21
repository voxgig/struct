#!perl
# The shared corpus, run on the shared runner.
#
# Every group in `build/test/test.json` is driven through voxgig/omni (see
# t/OmniBridge.pm), so this file only says WHICH subject answers each group
# and with which flags - the entry loop, the comparison, the error and
# `match` handling all live in the runner, identically for every port.
#
# Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.

use 5.018;
use strict;
use warnings;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin";

use Voxgig::Struct qw();
use Scalar::Util ();

use OmniBridge;

my $corpus = "$FindBin::Bin/../../build/test/test.json";
plan skip_all => "Corpus file not found: $corpus" unless -e $corpus;

my $NULLMARK = $OmniBridge::NULLMARK;

my $run  = OmniBridge::make_run('struct');
my $spec = $run->{spec};

# One group, omni's default flags (`null` on).
sub runset {
    my ( $label, $testspec, $subject ) = @_;
    return group( $label, $testspec, {}, $subject );
}

# One group with explicit flags.
sub runsetflags {
    my ( $label, $testspec, $flags, $subject ) = @_;
    return group( $label, $testspec, $flags, $subject );
}

# Each group is one Test::More assertion, so a failure names the group and
# the entry (omni's message carries the index, the entry and both values).
sub group {
    my ( $label, $testspec, $flags, $subject ) = @_;
    my $ok = eval { $run->{runsetflags}->( $testspec, $flags, $subject ); 1 };
    if ($ok) {
        pass($label);
        return 1;
    }
    my $err = $@;
    fail($label);
    diag("$label: $err");
    return 0;
}

my $jbool = \&Voxgig::Struct::jbool;

# The three single-entry cases below are not sets, so they are compared here
# rather than by the runner. Map key order is not significant - `_stringify_inner`
# with the sort flag renders both sides the same way, as node's deepStrictEqual
# does.
sub canon { return Voxgig::Struct::_stringify_inner( $_[0], 1 ) }

# ===========================================================================
# minor
# ===========================================================================

my $minor = $spec->{minor};

runset( 'minor-isnode', $minor->{isnode}, sub { $jbool->( Voxgig::Struct::isnode( $_[0] ) ) } );
runset( 'minor-ismap',  $minor->{ismap},  sub { $jbool->( Voxgig::Struct::ismap( $_[0] ) ) } );
runset( 'minor-islist', $minor->{islist}, sub { $jbool->( Voxgig::Struct::islist( $_[0] ) ) } );

runsetflags( 'minor-iskey', $minor->{iskey}, { null => 0 },
    sub { $jbool->( Voxgig::Struct::iskey( $_[0] ) ) } );

runsetflags( 'minor-strkey', $minor->{strkey}, { null => 0 },
    sub { Voxgig::Struct::strkey( $_[0] ) } );

runsetflags( 'minor-isempty', $minor->{isempty}, { null => 0 },
    sub { $jbool->( Voxgig::Struct::isempty( $_[0] ) ) } );

runset( 'minor-isfunc', $minor->{isfunc}, sub { $jbool->( Voxgig::Struct::isfunc( $_[0] ) ) } );

runsetflags( 'minor-clone', $minor->{clone}, { null => 0 },
    sub { Voxgig::Struct::clone( $_[0] ) } );

# The corpus names the predicate; the test file supplies it.
my %checkmap = (
    gt3 => sub { $_[0][1] > 3 },
    lt3 => sub { $_[0][1] < 3 },
);
runset( 'minor-filter', $minor->{filter},
    sub { Voxgig::Struct::filter( $_[0]{val}, $checkmap{ $_[0]{check} } ) } );

runset( 'minor-flatten', $minor->{flatten},
    sub { Voxgig::Struct::flatten( $_[0]{val}, $_[0]{depth} ) } );

runset( 'minor-escre',  $minor->{escre},  sub { Voxgig::Struct::escre( $_[0] ) } );
runset( 'minor-escurl', $minor->{escurl}, sub { Voxgig::Struct::escurl( $_[0] ) } );

runset(
    'minor-stringify',
    $minor->{stringify},
    sub {
        my ($in)  = @_;
        my $val   = $in->{val};
        my $isnul = defined $val && !ref $val && $val eq $NULLMARK;
        return Voxgig::Struct::stringify( $isnul ? 'null' : $val, $in->{max} );
    }
);

runsetflags( 'minor-jsonify', $minor->{jsonify}, { null => 0 },
    sub { Voxgig::Struct::jsonify( $_[0]{val}, $_[0]{flags} ) } );

# `null: true`, so an absent path arrives as NULLMARK and the rendered path
# has to be put back the way canonical renders a real undefined.
runsetflags(
    'minor-pathify',
    $minor->{pathify},
    { null => 1 },
    sub {
        my ($in)  = @_;
        my $raw   = $in->{path};
        my $isnul = defined $raw && !ref $raw && $raw eq $NULLMARK;
        my $path  = $isnul ? undef : $raw;
        my $str   = Voxgig::Struct::pathify( $path, $in->{from} );
        $str =~ s/\Q$NULLMARK\E\.//;
        $str =~ s/>/:null>/g if $isnul;
        return $str;
    }
);

runset( 'minor-items',  $minor->{items},  sub { Voxgig::Struct::items( $_[0] ) } );
runset( 'minor-keysof', $minor->{keysof}, sub { Voxgig::Struct::keysof( $_[0] ) } );

# `alt` is omitted where the corpus omits it: passing an explicit undef is a
# different call, and getelem/getprop differ on whether a NULL alt counts.
runsetflags(
    'minor-getelem',
    $minor->{getelem},
    { null => 0 },
    sub {
        my ($in) = @_;
        my $alt = $in->{alt};
        return ( !defined $alt || Voxgig::Struct::is_jnull($alt) )
          ? Voxgig::Struct::getelem( $in->{val}, $in->{key} )
          : Voxgig::Struct::getelem( $in->{val}, $in->{key}, $alt );
    }
);

runsetflags(
    'minor-getprop',
    $minor->{getprop},
    { null => 0 },
    sub {
        my ($in) = @_;
        return exists $in->{alt}
          ? Voxgig::Struct::getprop( $in->{val}, $in->{key}, $in->{alt} )
          : Voxgig::Struct::getprop( $in->{val}, $in->{key} );
    }
);

runset( 'minor-setprop', $minor->{setprop},
    sub { Voxgig::Struct::setprop( $_[0]{parent}, $_[0]{key}, $_[0]{val} ) } );

runset( 'minor-delprop', $minor->{delprop},
    sub { Voxgig::Struct::delprop( $_[0]{parent}, $_[0]{key} ) } );

runsetflags( 'minor-haskey', $minor->{haskey}, { null => 0 },
    sub { $jbool->( Voxgig::Struct::haskey( $_[0]{src}, $_[0]{key} ) ) } );

runsetflags( 'minor-join', $minor->{join}, { null => 0 },
    sub { Voxgig::Struct::join( $_[0]{val}, $_[0]{sep}, $_[0]{url} ) } );

runset( 'minor-typename', $minor->{typename}, sub { Voxgig::Struct::typename( $_[0] ) } );

runsetflags( 'minor-typify', $minor->{typify}, { null => 0 },
    sub { Voxgig::Struct::typify( $_[0] ) } );

runsetflags( 'minor-size', $minor->{size}, { null => 0 },
    sub { Voxgig::Struct::size( $_[0] ) } );

runsetflags( 'minor-slice', $minor->{slice}, { null => 0 },
    sub { Voxgig::Struct::slice( $_[0]{val}, $_[0]{start}, $_[0]{end} ) } );

runsetflags( 'minor-pad', $minor->{pad}, { null => 0 },
    sub { Voxgig::Struct::pad( $_[0]{val}, $_[0]{pad}, $_[0]{char} ) } );

# setpath rewrites `store` IN PLACE, and eight of these nine entries assert
# that rewrite through `match.args`. The bridge hands the subject omni's own
# hash, so the runner sees it (t/OmniBridge.pm).
runsetflags( 'minor-setpath', $minor->{setpath}, { null => 0 },
    sub { Voxgig::Struct::setpath( $_[0]{store}, $_[0]{path}, $_[0]{val} ) } );

# ===========================================================================
# walk
# ===========================================================================

runset(
    'walk-basic',
    $spec->{walk}{basic},
    sub {
        my $walkpath = sub {
            my ( $_key, $val, $_parent, $path ) = @_;
            return $val if ref $val || !defined $val;
            return $val if !Voxgig::Struct::_is_string_sv($val);
            return $val . '~' . CORE::join( '.', @$path );
        };
        return Voxgig::Struct::walk( $_[0], $walkpath );
    }
);

runsetflags(
    'walk-depth',
    $spec->{walk}{depth},
    { null => 0 },
    sub {
        my ($in) = @_;
        my ( $top, $cur );
        my $copy = sub {
            my ( $key, $val, $_parent, $_path ) = @_;
            if ( !defined $key || Voxgig::Struct::isnode($val) ) {
                my $child = Voxgig::Struct::islist($val) ? [] : Voxgig::Struct::jm();
                if ( !defined $key ) { $top = $cur = $child }
                else {
                    Voxgig::Struct::setprop( $cur, $key, $child );
                    $cur = $child;
                }
            }
            else {
                Voxgig::Struct::setprop( $cur, $key, $val );
            }
            return $val;
        };
        Voxgig::Struct::walk( $in->{src}, $copy, undef, $in->{maxdepth} );
        return $top;
    }
);

runset(
    'walk-copy',
    $spec->{walk}{copy},
    sub {
        my ($in) = @_;
        my $cur;
        my $walkcopy = sub {
            my ( $key, $val, $_parent, $path ) = @_;
            if ( !defined $key ) {
                $cur = [];
                $cur->[0] =
                    Voxgig::Struct::ismap($val)  ? Voxgig::Struct::jm()
                  : Voxgig::Struct::islist($val) ? []
                  :                                $val;
                return $val;
            }

            my $v = $val;
            my $i = Voxgig::Struct::size($path);

            if ( Voxgig::Struct::isnode($v) ) {
                $v = $cur->[$i] =
                  Voxgig::Struct::ismap($v) ? Voxgig::Struct::jm() : [];
            }

            Voxgig::Struct::setprop( $cur->[ $i - 1 ], $key, $v );

            return $val;
        };
        Voxgig::Struct::walk( $in, $walkcopy );
        return $cur->[0];
    }
);

# ===========================================================================
# merge
# ===========================================================================

# `merge.basic` is a single entry, not a set.
{
    my $basic = Voxgig::Struct::clone( $spec->{merge}{basic} );
    is( canon( Voxgig::Struct::merge( $basic->{in} ) ),
        canon( $basic->{out} ), 'merge-basic' );
}

runset( 'merge-cases', $spec->{merge}{cases}, sub { Voxgig::Struct::merge( $_[0] ) } );
runset( 'merge-array', $spec->{merge}{array}, sub { Voxgig::Struct::merge( $_[0] ) } );

# All six entries assert the in-place result through `match.args`.
runset( 'merge-integrity', $spec->{merge}{integrity}, sub { Voxgig::Struct::merge( $_[0] ) } );

runset( 'merge-depth', $spec->{merge}{depth},
    sub { Voxgig::Struct::merge( $_[0]{val}, $_[0]{depth} ) } );

# ===========================================================================
# getpath
# ===========================================================================

my $getpath = $spec->{getpath};

runset( 'getpath-basic', $getpath->{basic},
    sub { Voxgig::Struct::getpath( $_[0]{store}, $_[0]{path} ) } );

runset(
    'getpath-relative',
    $getpath->{relative},
    sub {
        my ($in) = @_;
        my $dpath = $in->{dpath};
        return Voxgig::Struct::getpath(
            $in->{store},
            $in->{path},
            {
                dparent => $in->{dparent},
                ( defined $dpath && !ref $dpath ? ( dpath => [ split /\./, $dpath ] ) : () ),
            }
        );
    }
);

runset( 'getpath-special', $getpath->{special},
    sub { Voxgig::Struct::getpath( $_[0]{store}, $_[0]{path}, $_[0]{inj} ) } );

runset(
    'getpath-handler',
    $getpath->{handler},
    sub {
        my ($in) = @_;
        return Voxgig::Struct::getpath(
            Voxgig::Struct::jm( '$TOP', $in->{store}, '$FOO', sub { 'foo' } ),
            $in->{path},
            { handler => sub { my ( $_inj, $val, $_cur, $_ref ) = @_; return $val->() } },
        );
    }
);

# ===========================================================================
# inject
# ===========================================================================

# The runner encodes "value is JSON null" as the NULLMARK string so it
# survives a JSON round trip; a modifier puts a real null back as the
# structure is built. omni's own nullmodifier writes omni's null (undef),
# so this port supplies its own, writing JNULL.
my $nullmodifier = sub {
    my ( $val, $key, $parent ) = @_;
    return if !defined $parent || !ref $parent;
    return if ref $val || !defined $val;

    if ( $val eq $NULLMARK ) {
        Voxgig::Struct::setprop( $parent, $key, Voxgig::Struct::JNULL() );
    }
    elsif ( 0 <= index( $val, $NULLMARK ) ) {
        my $text = $val;
        $text =~ s/\Q$NULLMARK\E/null/g;
        Voxgig::Struct::setprop( $parent, $key, $text );
    }
    return;
};

# `inject.basic` is a single entry, not a set.
{
    my $basic = Voxgig::Struct::clone( $spec->{inject}{basic} );
    is( canon( Voxgig::Struct::inject( $basic->{in}{val}, $basic->{in}{store} ) ),
        canon( $basic->{out} ), 'inject-basic' );
}

runset( 'inject-string', $spec->{inject}{string},
    sub { Voxgig::Struct::inject( $_[0]{val}, $_[0]{store}, { modify => $nullmodifier } ) } );

runset( 'inject-deep', $spec->{inject}{deep},
    sub { Voxgig::Struct::inject( $_[0]{val}, $_[0]{store} ) } );

# ===========================================================================
# transform
# ===========================================================================

my $transform = $spec->{transform};

# `transform.basic` is a single entry, not a set.
{
    my $basic = Voxgig::Struct::clone( $transform->{basic} );
    is( canon( Voxgig::Struct::transform( $basic->{in}{data}, $basic->{in}{spec} ) ),
        canon( $basic->{out} ), 'transform-basic' );
}

for my $section (qw(paths cmds each pack ref apply)) {
    runset( "transform-$section", $transform->{$section},
        sub { Voxgig::Struct::transform( $_[0]{data}, $_[0]{spec} ) } );
}

runsetflags( 'transform-format', $transform->{format}, { null => 0 },
    sub { Voxgig::Struct::transform( $_[0]{data}, $_[0]{spec} ) } );

runset(
    'transform-modify',
    $transform->{modify},
    sub {
        my ($in) = @_;
        return Voxgig::Struct::transform(
            $in->{data},
            $in->{spec},
            {
                modify => sub {
                    my ( $val, $key, $parent ) = @_;
                    return if !defined $key || !defined $parent || !ref $parent;
                    return if ref $val || !defined $val;
                    return if !Voxgig::Struct::_is_string_sv($val);
                    Voxgig::Struct::setprop( $parent, $key, '@' . $val );
                    return;
                }
            }
        );
    }
);

# ===========================================================================
# validate
# ===========================================================================

my $validate = $spec->{validate};

runsetflags( 'validate-basic', $validate->{basic}, { null => 0 },
    sub { Voxgig::Struct::validate( $_[0]{data}, $_[0]{spec} ) } );

for my $section (qw(child one exact)) {
    runset( "validate-$section", $validate->{$section},
        sub { Voxgig::Struct::validate( $_[0]{data}, $_[0]{spec} ) } );
}

runsetflags( 'validate-invalid', $validate->{invalid}, { null => 0 },
    sub { Voxgig::Struct::validate( $_[0]{data}, $_[0]{spec} ) } );

runset( 'validate-special', $validate->{special},
    sub { Voxgig::Struct::validate( $_[0]{data}, $_[0]{spec}, $_[0]{inj} ) } );

# ===========================================================================
# select
# ===========================================================================

my $select = $spec->{select};

for my $section (qw(basic operators edge alts)) {
    runset( "select-$section", $select->{$section},
        sub { Voxgig::Struct::select( $_[0]{obj}, $_[0]{query} ) } );
}

# `null: false` keeps a JSON null an ACTUAL null rather than the NULLMARK
# string, so select sees a present-but-null field.
runsetflags( 'select-nullkey', $select->{nullkey}, { null => 0 },
    sub { Voxgig::Struct::select( $_[0]{obj}, $_[0]{query} ) } );

# ===========================================================================
# regex (parity floor: Go stdlib regexp - see design/REGEX_API.md)
# ===========================================================================

my $regex = $spec->{regex};

runset( 'regex-test', $regex->{test},
    sub { $jbool->( Voxgig::Struct::re_test( $_[0]{pattern}, $_[0]{input} ) ) } );

runset( 'regex-find', $regex->{find},
    sub { Voxgig::Struct::re_find( $_[0]{pattern}, $_[0]{input} ) } );

runset( 'regex-find_all', $regex->{find_all},
    sub { Voxgig::Struct::re_find_all( $_[0]{pattern}, $_[0]{input} ) } );

runset( 'regex-replace', $regex->{replace},
    sub { Voxgig::Struct::re_replace( $_[0]{pattern}, $_[0]{input}, $_[0]{replacement} ) } );

runset( 'regex-escape', $regex->{escape},
    sub { Voxgig::Struct::re_escape( $_[0]{val} ) } );

# ===========================================================================
# sentinels - null and absent unified on observation
# ===========================================================================

my $sentinels = $spec->{sentinels};

runsetflags( 'sentinels-getprop_unify', $sentinels->{getprop_unify}, { null => 0 },
    sub { Voxgig::Struct::getprop( $_[0]{val}, $_[0]{key}, $_[0]{alt} ) } );

runsetflags( 'sentinels-getelem_absent', $sentinels->{getelem_absent}, { null => 0 },
    sub { Voxgig::Struct::getelem( $_[0]{val}, $_[0]{key}, $_[0]{alt} ) } );

runsetflags( 'sentinels-haskey_unify', $sentinels->{haskey_unify}, { null => 0 },
    sub { $jbool->( Voxgig::Struct::haskey( $_[0]{val}, $_[0]{key} ) ) } );

runsetflags( 'sentinels-isempty_unify', $sentinels->{isempty_unify}, { null => 0 },
    sub { $jbool->( Voxgig::Struct::isempty( $_[0] ) ) } );

runsetflags( 'sentinels-isnode_unify', $sentinels->{isnode_unify}, { null => 0 },
    sub { $jbool->( Voxgig::Struct::isnode( $_[0] ) ) } );

runsetflags( 'sentinels-stringify_null', $sentinels->{stringify_null}, { null => 0 },
    sub { Voxgig::Struct::stringify( $_[0] ) } );

# ===========================================================================
# condense
# ===========================================================================
#
# `condense`, `expand` and `iscondensed` exist only in canonical TypeScript so
# far - no other port implements them, and this one does not either. The three
# groups (37 entries) are named here rather than left silent so the gap is a
# visible TODO instead of a group nobody notices is missing.
{
    my @missing = grep { !Voxgig::Struct->can($_) } qw(condense expand iscondensed);
    diag( 'condense not ported: skipping ' . scalar(@missing) . ' group(s)' ) if @missing;
}

done_testing();
