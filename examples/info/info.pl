#
# The First Basic Report
# Cosimo Streppone <cosimo@cpan.org>
# 2006-03-14
#
# $Id: info.pl,v 1.1 2006/03/14 17:14:24 cosimo Exp $

use strict;
use warnings;
use PDF::ReportWriter;

my $rw = PDF::ReportWriter->new();
$rw->render_report('./info.xml');
$rw->save();

