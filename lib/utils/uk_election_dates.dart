/// Approximate UK local-election polling day for [year]: by convention,
/// English/Welsh local elections are held on the first Thursday in May.
/// No per-council per-year polling date exists in this app's data pipeline
/// (only a bare election year survives), so this is a deliberate estimate
/// for display purposes, not a historical record.
DateTime approximateUkLocalElectionDate(int year) {
  var date = DateTime(year, 5, 1);
  while (date.weekday != DateTime.thursday) {
    date = date.add(const Duration(days: 1));
  }
  return date;
}
