# Test Provider (prototype) — Perl port of the canonical ts/provider.ts.
#
# Reads the shared corpus (build/test/test.json) and hands test code clean,
# normalized cases. It is NOT a test runner: it never calls the subject and
# never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
#
# Zero runtime dependencies: CORE modules only. JSON booleans use JSON::PP
# (a core module). Perl hashes are unordered, so to preserve the corpus key
# order for functions()/groups() we parse the JSON with a tiny pure-Perl
# recursive-descent reader that records first-seen key order into an inline
# insertion-ordered tied hash (OrderedHash, below). Values (numbers, strings,
# booleans, null, nested maps/lists) decode to the same shapes JSON::PP would
# yield: JSON::PP::Boolean for true/false, undef for null.

package Voxgig::Struct::Proto;

use strict;
use warnings;
use Exporter 'import';
use File::Spec;
use File::Basename qw(dirname);
use JSON::PP ();

our @EXPORT_OK = qw(
    matchval equal equal_strict struct_match error_matches stringify
);

my $NULLMARK   = '__NULL__';
my $UNDEFMARK  = '__UNDEF__';
my $EXISTSMARK = '__EXISTS__';

# ─── inline insertion-ordered hash ──────────────────────────────────────────
# A minimal tied hash that remembers key insertion order. It behaves as an
# ordained hashref for all normal access; ->ordered_keys gives corpus order.

{
    package Voxgig::Struct::Proto::OrderedHash;

    sub TIEHASH {
        my ($class) = @_;
        return bless { keys => [], data => {} }, $class;
    }
    sub STORE {
        my ($self, $k, $v) = @_;
        push @{ $self->{keys} }, $k unless exists $self->{data}{$k};
        $self->{data}{$k} = $v;
    }
    sub FETCH    { $_[0]->{data}{ $_[1] } }
    sub EXISTS   { exists $_[0]->{data}{ $_[1] } }
    sub DELETE   {
        my ($self, $k) = @_;
        @{ $self->{keys} } = grep { $_ ne $k } @{ $self->{keys} };
        delete $self->{data}{$k};
    }
    sub CLEAR    { $_[0]->{keys} = []; $_[0]->{data} = {} }
    sub FIRSTKEY { $_[0]->{iter} = 0; $_[0]->{keys}[0] }
    sub NEXTKEY  {
        my ($self) = @_;
        return $self->{keys}[ ++$self->{iter} ];
    }
    sub SCALAR   { scalar %{ $_[0]->{data} } }
}

# Make a fresh ordered hashref.
sub _ordered_hash {
    my %h;
    tie %h, 'Voxgig::Struct::Proto::OrderedHash';
    return \%h;
}

# Ordered keys of a (possibly ordered) hashref. Falls back to plain keys.
sub _okeys {
    my ($h) = @_;
    my $t = tied %$h;
    return @{ $t->{keys} } if $t;
    return keys %$h;
}

# ─── tiny order-preserving JSON reader ──────────────────────────────────────
# Recursive descent over the raw text. Numbers/strings/null/true/false decode
# to plain Perl scalars / undef / JSON::PP::Boolean. Objects become ordered.

sub _parse_json {
    my ($text) = @_;
    my $pos = 0;
    my $val = _p_value($text, \$pos);
    _p_ws($text, \$pos);
    die "Trailing content in JSON at offset $pos\n" if $pos < length $text;
    return $val;
}

sub _p_ws {
    my ($t, $p) = @_;
    pos($t) = $$p;
    $t =~ /\G[\x20\x09\x0A\x0D]*/gc;
    $$p = pos($t);
}

sub _p_value {
    my ($t, $p) = @_;
    _p_ws($t, $p);
    my $c = substr($t, $$p, 1);
    return _p_object($t, $p) if $c eq '{';
    return _p_array($t, $p)  if $c eq '[';
    return _p_string($t, $p) if $c eq '"';
    if ($c eq 't') { $$p += 4; return JSON::PP::true }
    if ($c eq 'f') { $$p += 5; return JSON::PP::false }
    if ($c eq 'n') { $$p += 4; return undef }
    return _p_number($t, $p);
}

sub _p_object {
    my ($t, $p) = @_;
    my $obj = _ordered_hash();
    $$p++;    # consume {
    _p_ws($t, $p);
    if (substr($t, $$p, 1) eq '}') { $$p++; return $obj }
    while (1) {
        _p_ws($t, $p);
        my $key = _p_string($t, $p);
        _p_ws($t, $p);
        $$p++;    # consume :
        my $v = _p_value($t, $p);
        $obj->{$key} = $v;
        _p_ws($t, $p);
        my $c = substr($t, $$p, 1);
        $$p++;
        last if $c eq '}';
        # else c eq ',' → continue
    }
    return $obj;
}

sub _p_array {
    my ($t, $p) = @_;
    my @arr;
    $$p++;    # consume [
    _p_ws($t, $p);
    if (substr($t, $$p, 1) eq ']') { $$p++; return \@arr }
    while (1) {
        my $v = _p_value($t, $p);
        push @arr, $v;
        _p_ws($t, $p);
        my $c = substr($t, $$p, 1);
        $$p++;
        last if $c eq ']';
        # else ',' → continue
    }
    return \@arr;
}

my %ESC = (
    '"' => '"', '\\' => '\\', '/' => '/',
    'b' => "\b", 'f' => "\f", 'n' => "\n", 'r' => "\r", 't' => "\t",
);

sub _p_string {
    my ($t, $p) = @_;
    $$p++;    # consume opening "
    my $out = '';
    while (1) {
        my $c = substr($t, $$p, 1);
        if ($c eq '"') { $$p++; last }
        if ($c eq '\\') {
            my $e = substr($t, $$p + 1, 1);
            if ($e eq 'u') {
                my $hex = substr($t, $$p + 2, 4);
                $out .= chr(hex($hex));
                $$p += 6;
            }
            else {
                $out .= $ESC{$e} // $e;
                $$p += 2;
            }
        }
        else {
            $out .= $c;
            $$p++;
        }
    }
    return $out;
}

sub _p_number {
    my ($t, $p) = @_;
    pos($t) = $$p;
    $t =~ /\G(-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)/gc;
    my $num = $1;
    $$p = pos($t);
    return $num + 0;
}

# ─── default corpus path ────────────────────────────────────────────────────
# build/test/test.json relative to this module file (test/proto/perl).

sub _default_testfile {
    my $here = dirname(__FILE__);    # test/proto/perl
    return File::Spec->catfile($here, '..', '..', '..', 'build', 'test', 'test.json');
}

# ─── provider ───────────────────────────────────────────────────────────────

sub load {
    my ($class, $testfile) = @_;
    # Allow both Voxgig::Struct::Proto->load(...) and load(...) call styles.
    unless (defined $class && $class eq __PACKAGE__) {
        $testfile = $class;
        $class    = __PACKAGE__;
    }
    $testfile = _default_testfile() unless defined $testfile;
    open my $fh, '<:raw', $testfile or die "Cannot open $testfile: $!\n";
    local $/;
    my $text = <$fh>;
    close $fh;
    my $spec = _parse_json($text);
    return bless { spec => $spec }, $class;
}

sub raw {
    my ($self) = @_;
    return $self->{spec};
}

# A group bag is a map with a `set` array.
sub _is_group_bag {
    my ($v) = @_;
    return 0 unless _is_map($v);
    my $set = $v->{set};
    return ($set && ref($set) eq 'ARRAY') ? 1 : 0;
}

# A function node has at least one child group bag (excluding `name`).
sub _has_groups {
    my ($v) = @_;
    return 0 unless _is_map($v);
    for my $k (_okeys($v)) {
        next if $k eq 'name';
        return 1 if _is_group_bag($v->{$k});
    }
    return 0;
}

sub _fn_node {
    my ($self, $fn) = @_;
    my $spec = $self->{spec};
    my $node;
    if (_is_map($spec->{struct}) && exists $spec->{struct}{$fn}) {
        $node = $spec->{struct}{$fn};
    }
    elsif (exists $spec->{$fn}) {
        $node = $spec->{$fn};
    }
    die "Unknown function: $fn\n" unless defined $node;
    return $node;
}

sub functions {
    my ($self) = @_;
    my $spec = $self->{spec};
    my $root = (_is_map($spec->{struct})) ? $spec->{struct} : $spec;
    return [ grep { _is_group_bag($root->{$_}) || _has_groups($root->{$_}) } _okeys($root) ];
}

sub groups {
    my ($self, $fn) = @_;
    my $node = $self->_fn_node($fn);
    return [ grep { $_ ne 'name' && _is_group_bag($node->{$_}) } _okeys($node) ];
}

sub entries {
    my ($self, $fn, $group) = @_;
    my $node = $self->_fn_node($fn);
    my @groups = defined $group ? ($group) : @{ $self->groups($fn) };
    my @out;
    for my $g (@groups) {
        my $bag = $node->{$g};
        next unless _is_group_bag($bag);
        my $set = $bag->{set};
        for (my $i = 0; $i < @$set; $i++) {
            push @out, _normalize($fn, $g, $i, $set->[$i]);
        }
    }
    return \@out;
}

# ─── value-shape helpers ────────────────────────────────────────────────────

sub _is_map  { defined $_[0] && ref($_[0]) eq 'HASH' }
sub _is_list { defined $_[0] && ref($_[0]) eq 'ARRAY' }

sub _is_jbool { ref($_[0]) eq 'JSON::PP::Boolean' }
sub _jtrue    { _is_jbool($_[0]) && $_[0] }    # JSON::PP::Boolean overloads bool

# ─── normalization ──────────────────────────────────────────────────────────

sub _normalize {
    my ($fn, $group, $index, $raw) = @_;
    my $h = {
        function => $fn,
        group    => $group,
        index    => $index,
        id       => (exists $raw->{id} && defined $raw->{id}) ? "$raw->{id}" : undef,
        doc      => (exists $raw->{doc} && _jtrue($raw->{doc})) ? 1 : 0,
        client   => (exists $raw->{client} && defined $raw->{client}) ? "$raw->{client}" : undef,
        input    => _resolve_input($raw),
        expect   => _resolve_expect($raw),
        raw      => $raw,
    };
    return $h;
}

sub _resolve_input {
    my ($raw) = @_;
    if (exists $raw->{ctx}) {
        return { kind => 'ctx', ctx => $raw->{ctx} };
    }
    if (exists $raw->{args}) {
        return { kind => 'args', args => $raw->{args} };
    }
    return { kind => 'in', in => (exists $raw->{in} ? $raw->{in} : undef) };
}

sub _parse_err {
    my ($err) = @_;
    if (_is_jbool($err) && $err) {
        return { any => 1, text => undef, regex => 0 };
    }
    if (!ref $err && defined $err) {
        if ($err =~ m{^/(.+)/$}s) {
            return { any => 0, text => $1, regex => 1 };
        }
        return { any => 0, text => $err, regex => 0 };
    }
    # Non-true, non-string err spec: treat as "any error".
    return { any => 1, text => undef, regex => 0 };
}

sub _resolve_expect {
    my ($raw) = @_;
    my $has_match = exists $raw->{match};
    my $match_part = $has_match ? $raw->{match} : undef;
    if (exists $raw->{err}) {
        return { kind => 'error', error => _parse_err($raw->{err}), match => $match_part };
    }
    if (exists $raw->{out}) {
        return { kind => 'value', value => $raw->{out}, match => $match_part };
    }
    if ($has_match) {
        return { kind => 'match', match => $raw->{match} };
    }
    return { kind => 'absent' };
}

# ─── pure comparison helpers ────────────────────────────────────────────────

# stringify(x) = x if already a (plain) string, else compact JSON.
# In Perl, scalars are stringy/numbery; we treat any non-ref defined scalar
# (that is not a JSON::PP::Boolean) as "already a string" and pass it through.
# Refs, undef, and booleans get compact-JSON encoded (allow_nonref handles
# bare scalars/undef should they reach the encoder).
sub stringify {
    my ($x) = @_;
    return $x if (defined $x && !ref $x);
    return JSON::PP->new->canonical(0)->allow_nonref->encode($x);
}

sub _norm_null {
    my ($x) = @_;
    return undef if (!defined $x);
    return undef if (!ref $x && $x eq $NULLMARK);
    if (_is_list($x)) {
        return [ map { _norm_null($_) } @$x ];
    }
    if (_is_map($x)) {
        my %o;
        for my $k (_okeys($x)) { $o{$k} = _norm_null($x->{$k}) }
        return \%o;
    }
    return $x;
}

sub _norm_mark {
    my ($x) = @_;
    return undef if (defined $x && !ref $x && $x eq $NULLMARK);
    if (_is_list($x)) {
        return [ map { _norm_mark($_) } @$x ];
    }
    if (_is_map($x)) {
        my %o;
        for my $k (_okeys($x)) { $o{$k} = _norm_mark($x->{$k}) }
        return \%o;
    }
    return $x;
}

sub matchval {
    my ($check, $base) = @_;
    return 1 if _scalar_eq($check, $base);
    if (defined $check && !ref $check) {
        my $basestr = stringify($base);
        if ($check =~ m{^/(.+)/$}s) {
            my $re = $1;
            return ($basestr =~ /$re/) ? 1 : 0;
        }
        return (index(lc $basestr, lc $check) >= 0) ? 1 : 0;
    }
    if (ref $check eq 'CODE') {
        return 1;
    }
    return 0;
}

# Scalar-level identity for matchval's `check === base` first branch.
sub _scalar_eq {
    my ($a, $b) = @_;
    my $an = !defined $a;
    my $bn = !defined $b;
    return 1 if $an && $bn;
    return 0 if $an || $bn;
    return 0 if ref $a || ref $b;
    # Numeric-ish vs string compare: use string eq (JSON scalars compare fine).
    return ($a eq $b) ? 1 : 0;
}

sub equal {
    my ($expected, $actual) = @_;
    return _deep_eq(_norm_null($expected), _norm_null($actual));
}

sub equal_strict {
    my ($expected, $actual) = @_;
    return _deep_eq(_norm_mark($expected), _norm_mark($actual));
}

sub _deep_eq {
    my ($a, $b) = @_;
    my $an = !defined $a;
    my $bn = !defined $b;
    return 1 if $an && $bn;
    return 0 if $an || $bn;
    if (_is_list($a) && _is_list($b)) {
        return 0 unless @$a == @$b;
        for (my $i = 0; $i < @$a; $i++) {
            return 0 unless _deep_eq($a->[$i], $b->[$i]);
        }
        return 1;
    }
    if (_is_map($a) && _is_map($b)) {
        my @ak = keys %$a;
        my @bk = keys %$b;
        return 0 unless @ak == @bk;
        for my $k (@ak) {
            return 0 unless exists $b->{$k};
            return 0 unless _deep_eq($a->{$k}, $b->{$k});
        }
        return 1;
    }
    return 0 if ref $a || ref $b;
    # Two non-ref scalars: compare via string (handles numbers and strings).
    return ($a eq $b) ? 1 : 0;
}

sub error_matches {
    my ($check, $message) = @_;
    return 1 if $check->{any};
    return 0 if !defined $check->{text};
    if ($check->{regex}) {
        my $re = $check->{text};
        return ($message =~ /$re/) ? 1 : 0;
    }
    return (index(lc $message, lc $check->{text}) >= 0) ? 1 : 0;
}

# Partial structural match: every leaf of `check` must match `base` at its path.
sub struct_match {
    my ($check, $base) = @_;
    my $result = { ok => 1 };
    _walk_leaves($check, [], sub {
        my ($val, $path) = @_;
        return unless $result->{ok};
        my $baseval = _getpath($base, $path);
        return if _scalar_eq($val, $baseval);
        if (defined $val && !ref $val && $val eq $UNDEFMARK && !defined $baseval) {
            return;
        }
        if (defined $val && !ref $val && $val eq $EXISTSMARK && defined $baseval) {
            return;
        }
        if (!matchval($val, $baseval)) {
            $result = { ok => 0, path => $path, expected => $val, actual => $baseval };
        }
    });
    return $result;
}

sub _is_node { _is_map($_[0]) || _is_list($_[0]) }

sub _walk_leaves {
    my ($node, $path, $fn) = @_;
    if (_is_list($node)) {
        for (my $i = 0; $i < @$node; $i++) {
            _walk_leaves($node->[$i], [ @$path, "$i" ], $fn);
        }
    }
    elsif (_is_map($node)) {
        for my $k (_okeys($node)) {
            _walk_leaves($node->{$k}, [ @$path, $k ], $fn);
        }
    }
    else {
        $fn->($node, $path);
    }
}

sub _getpath {
    my ($store, $path) = @_;
    my $cur = $store;
    for my $key (@$path) {
        return undef unless defined $cur;
        if (_is_list($cur)) {
            $cur = $cur->[ $key + 0 ];
        }
        elsif (_is_map($cur)) {
            $cur = $cur->{$key};
        }
        else {
            return undef;
        }
    }
    return $cur;
}

1;
