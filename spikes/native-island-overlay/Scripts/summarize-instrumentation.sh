#!/bin/bash
# Derive only same-clock marker intervals from one raw instrumentation JSONL
# file. It is intentionally a summary aid, not a substitute for manual proof.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") instrumentation.jsonl" >&2
}

[ "$#" -eq 1 ] || { usage; exit 64; }
log="$1"
[ -f "$log" ] || { echo "error: instrumentation log not found: $log" >&2; exit 1; }

/usr/bin/perl -ne '
  my ($event) = /"event"\s*:\s*"([^"]+)"/;
  my ($timestamp) = /"timestampNs"\s*:\s*"?(\d+)"?/;
  next unless defined $event && defined $timestamp;

  if ($event eq "launch_process_started") {
    $launch_start = $timestamp unless defined $launch_start;
  } elsif ($event eq "launch_usable") {
    if (defined $launch_start) {
      printf "launch_usable_ms\t%.3f\n", ($timestamp - $launch_start) / 1_000_000;
    } else {
      print "launch_usable_ms\tUNAVAILABLE (no launch_process_started marker)\n";
    }
  } elsif ($event eq "interaction_requested") {
    push @interaction_starts, $timestamp;
  } elsif ($event eq "interaction_rendered") {
    if (@interaction_starts) {
      $start = shift @interaction_starts;
      printf "interaction_rendered_ms\t%.3f\n", ($timestamp - $start) / 1_000_000;
    } else {
      print "interaction_rendered_ms\tUNAVAILABLE (no interaction_requested marker)\n";
    }
  }
  END {
    print "interaction_rendered_ms\tUNAVAILABLE (unpaired interaction_requested marker)\n" if @interaction_starts;
  }
' "$log"
