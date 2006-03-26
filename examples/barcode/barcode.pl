#
# A simple barcode report
# Cosimo Streppone <cosimo@cpan.org>
# 2006-03-15
#
# $Id: barcode.pl,v 1.1 2006/03/16 11:11:06 cosimo Exp $

use strict;
use PDF::ReportWriter;

my $rw = PDF::ReportWriter->new();
$rw->render_report('./barcode.xml');
$rw->save();
