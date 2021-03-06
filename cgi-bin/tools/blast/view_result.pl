#!/usr/bin/perl -w

# Take the output file produced by BLAST from blast_result.pl and create one or more graphs from it.
# The types of graphs that can be created are those made by Bio::GMOD::Blast::Graph and by my BlastGraph
# package in CXGN::Graphics. The latter produces a histogram of how conserved each individual base is
# with respect to the domains found by BLAST in database entries.
#
# - Evan, 9 / 30 / 05

use strict;
use English;
use File::Basename;
use HTML::Entities;

use Number::Bytes::Human ();

use CXGN::BioTools::SearchIOHTMLWriter;
use CXGN::Page;
use CXGN::BlastDB;

use Bio::SearchIO;

use CXGN::Graphics::BlastGraph; #Evan's package for conservedness histograms
use CXGN::Apache::Error;
use CXGN::Tools::List qw/str_in/;
use CXGN::Tools::Identifiers qw/link_identifier/;
use File::Slurp qw/slurp/;
use CXGN::Page::FormattingHelpers qw/info_section_html page_title_html columnar_table_html/;
use CatalystX::GlobalContext '$c';

use constant MAX_FORMATTABLE_REPORT_FILE_SIZE => 2_000_000;

our $page = CXGN::Page->new( "BLAST Search Report", "Rob");
our %params;

our $tempfiles_subdir_rel = File::Spec->catdir($c->config->{'tempfiles_subdir'},'blast'); #path relative to website root dir
our $tempfiles_subdir_abs = File::Spec->catdir($c->config->{'basepath'},$tempfiles_subdir_rel); #absolute path

my @arglist = qw/report_file outformat interface_type output_graphs seq_count program database/;
@params{@arglist} = $page->get_encoded_arguments(@arglist);
$params{report_file} =~ s/\///g; #remove any slashes.  that should stop any nefarious path monkeying

$params{program} =~ s/[^a-z]//g; #remove any non-letters

# get the name of the database w/o the directory names (not sure if this works for all datasets...)
if ($params{database}=~/\/(\w+?)$/) {
    $params{database} = $1;
}

#my ($bdb) = CXGN::BlastDB->search_ilike(title=> "%$params{database}%");
our ($bdb) = CXGN::BlastDB->from_id($params{database});

die "No such database" if (!$bdb);


my $raw_report_file       = File::Spec->catfile($tempfiles_subdir_abs,$params{report_file});
my $raw_report_url        = File::Spec->catfile($tempfiles_subdir_rel,$params{report_file});
my $formatted_report_file = format_report_file($raw_report_file);

#warn "got raw report file $raw_report_file, formatting $formatted_report_file\n";

$page->header();

# TODO: insert JS here to add site xref popups to onclicks of
#  a.blast_match_ident elements
print <<EOJS;
EOJS

print page_title_html('BLAST Results');

print <<EOH;
<div align="center" style="margin-bottom: 1em">
  Note: Please <b>do not bookmark</b> this page. BLAST results are automatically deleted after 7 days.
</div>
EOH

# check whether we actually got some blast hits
my $got_hits = 0;
open(my $res_fh, "<$formatted_report_file") or die "$! opening $formatted_report_file for reading";
while (<$res_fh>) {
  if (m/Sbjct:/) {
    $got_hits = 1;
    last;
  }
}
close $res_fh;
#force got_hits to 1 if the report file is other than -m 0
$got_hits = 1 unless $params{outformat} == 0;

print graphics_html($raw_report_file,$formatted_report_file,$got_hits);

# display the blast results
my $report_filesize = Number::Bytes::Human::format_bytes( -s $raw_report_file );
my $report_download_link = qq|[<a href="$raw_report_url">View / download raw report</a>] ($report_filesize)|;
my $report_text =
  !$got_hits ? 'No hits found.'
  : -s $raw_report_file > MAX_FORMATTABLE_REPORT_FILE_SIZE ? 'report too large to display, please right-click the link above to download it'
  : slurp($formatted_report_file);



print info_section_html( title => 'BLAST Report',
                         subtitle => $report_download_link,
                         collapsible => 1,
                         contents => <<EOH);
<div style="border: 1px solid gray; padding: 1em 2em 1em 2em">
$report_text
</div>
EOH

$page->footer();


###############################

sub format_report_file {

    my ($raw_report_file) = @_;

    # check if $raw_report_file exists
    unless (-e $raw_report_file) {
        my $message = "BLAST results are automatically deleted after 7 days. You may need to run your BLAST again. "
            . "If you feel you received this message in error, please <a href='http://www.sgn.cornell.edu/tools/contact.pl'>contact us</a>.";
        $page->message_page('BLAST results not found.',$message);
    }


    #don't do any formatting on report files that are huge
    return $raw_report_file if -s $raw_report_file > MAX_FORMATTABLE_REPORT_FILE_SIZE;

    my $formatted_report_file = File::Spec->catfile( $tempfiles_subdir_abs,
                                                     "$params{report_file}.formatted.html"
                                                     );

    #  return $formatted_report_file if -s $formatted_report_file;

    #for smaller reports, HTML format them
    my %bioperl_formats = ( 0 => 'blast', #< only do for regular output,
                            #not the tabular and xml, even
                            #though bioperl can parse
                            #these.  if people choose
                            #these, they probably don't
                            #want bioperl to munge it.
                            );
#    sub linkit { my $s = $_[0]; $s =~ s/^lcl\|//; link_identifier($s) || $s }

    sub linkit {
        my $bdb = shift;
        my $s = shift;

        $s =~ s/^lcl\|//;
        my $url = $bdb->identifier_url($s);
        return qq { <a class="blast_match_ident" href="$url">$s</a> };
    }

    my %custom_formatters = (
                             7 => sub {  ### XML
                                 my ($raw,$fmt) = @_;
                                 print $fmt qq|<pre>|;
                                 while (my $line = <$raw>) {
                                     $line = encode_entities($line);
                                     $line =~ s/(?<=&lt;BlastOutput_query-def&gt;)[^&\s]+/linkit($bdb,$MATCH)/e;
                                     $line =~ s/(?<=&lt;Hit_accession&gt;)[^&\s]+/linkit($bdb,$MATCH)/e;
                                     print $fmt $line;
                                 }
                                 print $fmt qq|</pre>\n|;
                             },

                             8 => sub { ## TABULAR, NO COMMENTS
                                 my ($raw,$fmt) = @_;
                                 my @data;
                                 while (my $line = <$raw>) {
                                     chomp $line;
                                     $line = encode_entities($line);
                                     my @fields = split /\t/,$line;
                                     @fields[0,1] = map {linkit($bdb,$_)} @fields[0,1];
                                     push @data, \@fields;
                                     #      print columnar_table_html( data => \@fields );
                                 }
                                 print $fmt columnar_table_html( data => \@data );
                             },

                             9 => sub { ## TABULAR WITH COMMENTS
                                 my ($raw,$fmt) = @_;
                                 print $fmt qq|<pre>|;
                                 while (my $line = <$raw>) {
                                     $line = encode_entities($line);
                                     if( $line =~ /^\s*#/ ) {
                                         $line =~ s/(?<=Query: )\S+/linkit($bdb,$MATCH)/e;
                                     } else {
                                         my @fields = split /\t/,$line;
                                         @fields[0,1] = map linkit($bdb,$_),@fields[0,1];
                                         $line = join "\t",@fields;
                                     }
                                     print $fmt $line;
                                 }
                                 print $fmt qq|</pre>\n|;
                             },
                             );

    if ( $params{seq_count} == 1 && $bioperl_formats{$params{outformat}}) {
        my $in = Bio::SearchIO->new(-format => $bioperl_formats{$params{outformat}}, -file   => "< $raw_report_file")
            or die "$! opening $raw_report_file for reading";
        #$writer is a  "blastxml" (NCBI BLAST XML) which will b an argument for constructing new Bio::SearchIO module
        my $writer = CXGN::BioTools::SearchIOHTMLWriter->new($params{database});
        my $out = Bio::SearchIO->new( -writer => $writer,
                                      -file   => "> $formatted_report_file",
                                      );
        $out->write_result($in->next_result);
    } else {
        open my $raw,$raw_report_file
            or die "$! opening $raw_report_file for reading";
        open my $fmt,'>',$formatted_report_file
            or die "$! opening $formatted_report_file for writing";

        if(my $formatter = $custom_formatters{$params{outformat}} ) {
            $formatter->($raw,$fmt);
        } else {
            print $fmt qq|<pre>|;
            while (my $line = <$raw>) {
                $line = encode_entities($line);
                $line =~ s/(?<=Query[=:]\s)(\S+)/linkit($bdb,$MATCH)/eg;
                #      $line =~ s/(?<=^>)(\S+)/linkit($bdb,$MATCH)/eg;
                print $fmt $line;
            }
            print $fmt qq|</pre>\n|;
        }
    }

    return $formatted_report_file;
}
##########################

sub graphics_html {
  my ($raw_report_file,$formatted_report_file,$got_hits) = @_;

  sub section { info_section_html( title => 'Graphics', collapsible => 1, empty_message => shift, contents => shift) }

  return section('not available for multiple query sequences') if $params{seq_count} > 1;

  return section('available for 0 - pairwise output format only') unless $params{outformat} == 0;

  return section('disabled by user') if $params{output_graphs}  eq 'none';

  return section('No BLAST hits, graphics not generated') unless $got_hits;

  #call the bioperl graph package for a graphic of the various alignments
  my $bioperl_graph =
    info_section_html( title => 'Alignment Summary',
                       is_subsection => 1,
                       collapsible => 1,
                       empty_message => 'disabled by user',
                       contents => $params{output_graphs} =~ /bioperl/
                         ? bioperl_graph_html($raw_report_file)
                         : '',
                     );

  #call Evan's BlastGraph package for a different type of graph
  my $evan_graph =
    info_section_html( title => 'Conservedness Histogram',
                       is_subsection => 1,
                       collapsible => 1,

                       $params{output_graphs} !~ /histogram/ ? ( empty_message => 'disabled by user' ) :
                       $params{program} !~ /blastn/ ? (empty_message => 'not available for '.uc($params{program})) :
                       (contents => conservedness_histogram_html($raw_report_file)),
                     );

  return section(undef,$bioperl_graph.$evan_graph);
}

#####################

sub conservedness_histogram_html {
  my ($raw_report_file) = @_;

  #graph variables for just Evan's graph package
  my $graph_img_filename = $page->tempname() . ".png";

  my $graph2 = CXGN::Graphics::BlastGraph->new( blast_outfile => $raw_report_file,
                                                graph_outfile => "$tempfiles_subdir_abs/$graph_img_filename",
                                              );

  return 'graphical display not available BLAST reports larger than 1 MB' if -s $raw_report_file > 1_000_000;

  my $errstr = $graph2->write_img();
  $errstr and die "<b>ERROR:</b> $errstr";


  return join '',
    ( <<EOH,
<center><b>Conservedness Histogram</b></center>
<p>The histogram shows a count of hits <i>for each base</i> in the query sequence,
but counts <i>only the domains BLAST finds</i>, meaning this is really more a function of region than of individual base.
Within the graph, green shows exact base matches within conserved regions; blue shows non-matching bases within conserved regions. Gaps introduced into the query by BLAST are ignored; gaps introduced into target sequences are not.</p>
EOH
      $graph2->get_map_html(), #code for map element (should have the name used below in the image)
      qq|<div align="center" style="color: #777777">|,
      qq|<img src="$tempfiles_subdir_rel/$graph_img_filename" border="2" usemap="#graph2map" alt="" />|,
      qq|</div>\n\n|,
    );

}


#################

sub bioperl_graph_html {
  my ($raw_report_file) = @_;
  return unless -e $raw_report_file;
  return 'graphical display not available for BLAST reports larger than 1 MB' if -s $raw_report_file > 1_000_000;

  my $inc_str = join ',', map qq|"$_"|, @INC;
  my $cmd = <<EOP;
    \@INC = ( $inc_str );
    require Bio::GMOD::Blast::Graph;
    my \$graph = Bio::GMOD::Blast::Graph->new(-outputfile => "$raw_report_file",
                                              -dstDir => "$tempfiles_subdir_abs/",
                                              -dstURL => "$tempfiles_subdir_rel/",
                                              -imgName=> "$params{report_file}.png",
                                             );
    die unless \$graph;
    \$graph->showGraph();
EOP

  my $html = `perl -e '$cmd'`;
  return $html;
}
