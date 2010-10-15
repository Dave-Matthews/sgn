package SGN::Test::Data;

use strict;
use warnings;
use Bio::Chado::Schema::Sequence::Feature;
use SGN::Context;
use base 'Exporter';
use Test::More;

our $schema;

BEGIN {
    my $db_profile = 'sgn_test';
    eval {
        $schema = SGN::Context->new->dbic_schema('Bio::Chado::Schema', $db_profile)
    };
    if ($@) {
        plan skip_all => "Could not create a db connection. Do  you have the $db_profile db profile?";
    }
}

=head1 NAME

SGN::Test::Data - create Bio::Chado::Schema test objects

=head1 SYNOPSIS

    use lib 't/lib';
    use SGN::Test::Data qw/create_test/;

    my $schema = SGN::Context->new->dbic_schema('Bio::Chado::Schema', 'sgn_test');
    # all other necessary objects are auto-created, such as
    # cvterms, dbxrefs, features, etc...
    my $organism = create_test('Organism::Organism',{
        genus        => 'Tyrannosaurus',
        species      => 'Tyrannosaurus rex',
        common_name  => 'Tyrant King',
        comment      => 'Small hands',
        abbreviation => 'TREX',
    });

    my $feature = create_test('Sequence::Feature',{
        residues => 'GATTACA',
        organism => $organism,
    });

    # pre-created objects can be passed in, to specify linking objects
    my $gene_cvterm     = create_test('Cv::Cvterm', { name  => 'gene' });
    my $gene_feature    = create_test('Sequence::Feature', { type => $gene_cvterm });
    my $gene_featureloc = create_test('Sequence::Featureloc', { feature => $gene_feature });

    my $featureprop = create_test('Sequence::Featureprop', { value => 'Amazing!' });

=head1 FUNCTIONS

=head2 create_test

This function takes the name of a Bio::Chado::Schema object, such as 'Sequence::Feature', as the first argument, and an optional hash ref of parameters that will be passed to the appropriate C<create> function.

All unspecified parameters that are necessary will get auto-created values, and all necessary linking objects will be autocreated.

YOU DO NOT HAVE TO CLEAN UP THESE OBJECTS. All SGN::Test::Data objects auto-destruct at END time, by having their C<delete> method called.

=cut

our $num_features = 0;
our $num_cvterms = 0;
our $num_dbxrefs = 0;
our $num_dbs = 0;
our $num_cvs = 0;
our $num_organisms = 0;
our $test_data = [];
our @EXPORT_OK = qw/ create_test /;

sub create_test {
    my ($pkg, $values) = @_;
    die "Must provide package name to create test object" unless $pkg;
    my $pkg_subs = {
        'Cv::Cv'               => sub { _create_test_cv($values) },
        'Cv::Cvterm'           => sub { _create_test_cvterm($values) },
        'General::Db'          => sub { _create_test_db($values) },
        'General::Dbxref'      => sub { _create_test_dbxref($values) },
        'Sequence::Feature'    => sub { _create_test_feature($values) },
        'Organism::Organism'   => sub { _create_test_organism($values) },
        'Sequence::Featureloc' => sub { _create_test_featureloc($values) },
        'Sequence::Featureprop' => sub { _create_test_featureprop($values) },
        'Sequence::FeatureRelationship' => sub { _create_test_featurerelationship($values) },

    };
    die "$pkg creation not supported yet, sorry" unless exists $pkg_subs->{$pkg};
    return $pkg_subs->{$pkg}->($values);
}

sub _create_test_db {
    my ($values) = @_;
    my $db = $schema->resultset('General::Db')
           ->create( { name => $values->{name} || "db_$num_dbs-$$" } );
    push @$test_data, $db;
    $num_dbs++;
    return $db;
}

sub _create_test_dbxref {
    my ($values) = @_;

    $values->{db} ||= _create_test_db();

    $values->{accession} ||= "dbxref_$num_dbxrefs-$$";
    my @values = keys %$values;

    my $dbxref = $schema->resultset('General::Dbxref')
           ->create(
            {
                db_id     => $values->{db}->db_id,
                # some things have null constraints, so default to zero
                map { $_  => $values->{$_} || 0 } @values,
            });
    push @$test_data, $dbxref;
    $num_dbxrefs++;
    return $dbxref;
}

sub _create_test_cv {
    my ($values) = @_;

    $values->{name}       ||= "cv_$num_cvs-$$";
    $values->{definition} ||= "semantics";

    my $cv = $schema->resultset('Cv::Cv')
           ->create( $values );

    push @$test_data, $cv;
    $num_cvs++;
    return $cv;
}

sub _create_test_cvterm {
    my ($values) = @_;

    $values->{name}   ||= "cvterm_$num_cvterms-$$";

    my @values = keys %$values;

    $values->{dbxref} ||= _create_test_dbxref();
    $values->{cv}     ||= _create_test_cv();
    my $cvterm = $schema->resultset('Cv::Cvterm')
           ->create(
            {
                dbxref_id => $values->{dbxref}->dbxref_id,
                cv_id     => $values->{cv}->cv_id,
                map { $_  => $values->{$_} || 0 } @values,
            });
    push @$test_data, $cvterm;
    $num_cvterms++;
    return $cvterm;
}

sub _create_test_organism {
    my ($values) = @_;
    $values->{genus}   ||= "organism_$num_organisms-$$";
    $values->{species} ||= $values->{genus} . ' fooii';

    my $organism = $schema->resultset('Organism::Organism')
                          ->create( $values );
    push @$test_data, $organism;
    $num_organisms++;
    return $organism;

}

sub _create_test_feature {
    my ($values) = @_;


    # provide some defaults for things we don't care about
    $values->{seqlen}     ||= length($values->{residues});
    $values->{name}       ||= "feature_$num_features-$$";
    $values->{uniquename} ||= "unique_feature_$num_features-$$";

    my @values = keys %$values;
    $values->{residues}   //= 'ATCG';
    $values->{organism}   ||= _create_test_organism();
    $values->{type}       ||= _create_test_cvterm();
    $values->{dbxref}     ||= _create_test_dbxref();

    my $feature = $schema->resultset('Sequence::Feature')
           ->create({
                type_id     => $values->{type}->cvterm_id,
                organism_id => $values->{organism}->organism_id,
                dbxref_id   => $values->{dbxref}->dbxref_id,
                residues    => $values->{residues},
                map { $_ => $values->{$_} || 0 } @values,
           });
    push @$test_data, $feature;
    $num_features++;
    return $feature;
}

sub _create_test_featurerelationship {
    my ($values) = @_;

    my @values = grep { $_ ne 'object' and $_ ne 'subject' } keys %$values;

    $values->{type}       ||= _create_test_cvterm();

    # TODO: which gets the type created above?
    $values->{subject}    ||= _create_test_feature();
    $values->{object}     ||= _create_test_feature();

    my $featurerelationship = $schema->resultset('Sequence::FeatureRelationship')
        ->create({
                type_id     => $values->{type}->cvterm_id,
                subject_id  => $values->{subject}->feature_id,
                object_id   => $values->{object}->feature_id,
                map { $_    => $values->{$_} || 0 } @values,
        });
}

sub _create_test_featureprop {
    my ($values) = @_;

    $values->{feature}    ||= _create_test_feature();
    $values->{type}       ||= _create_test_cvterm();

    my $featureprop = $schema->resultset('Sequence::Featureprop')
        ->create({
            feature_id    => $values->{feature}->feature_id,
            type_id       => $values->{type}->cvterm_id,
            map { $_ => $values->{$_} || 0} qw/value rank/,
        });
}

sub _create_test_featureloc {
    my ($values) = @_;

    $values->{feature}    ||= _create_test_feature();
    $values->{srcfeature} ||= _create_test_feature();
    # the following values need to be consistent with the default
    # residue, which is 4 bases long
    $values->{fmin} ||= 1;
    $values->{fmax} ||= 3;

    my $featureloc = $schema->resultset('Sequence::Featureloc')
        ->create({
            feature_id    => $values->{feature}->feature_id,
            srcfeature_id => $values->{srcfeature}->feature_id,
            map { $_ => $values->{$_} || 0 }
                qw/
                    fmin fmax rank phase strand locgroup
                    is_fmax_partial residue_info
                  /,
        });
}

sub END {
    diag("deleting " . scalar(@$test_data) . " test data objects") if @$test_data;
    # delete objects in the reverse order we created them
    # TODO: catch signals?
    map {
        diag("deleting $_") if $ENV{DEBUG};
        my $deleted = $_->delete;
    } reverse @$test_data;
}

1;
