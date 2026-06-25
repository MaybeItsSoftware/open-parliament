import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/council_control.dart';

void main() {
  group('parseCouncils', () {
    const html = '''
      <table>
        <tr><th>Type</th><th>Council</th><th>Control</th><th>Lab</th><th>Con</th><th>Green</th><th>Total</th></tr>
        <tr><td>Scotland</td><td>Aberdeen City</td><td>SNP/LD</td><td>11</td><td>6</td><td>3</td><td>45</td></tr>
        <tr><td>District</td><td>Adur</td><td>LAB</td><td>17</td><td>0</td><td>2</td><td>29</td></tr>
        <tr><td>Other</td><td>City of London</td><td></td><td>0</td><td>0</td><td>0</td><td>100</td></tr>
        <tr><td></td><td>Totals:</td><td>&nbsp;</td><td>28</td><td>6</td><td>5</td><td>74</td></tr>
      </table>
    ''';

    test('extracts councils with type, control, seats and total', () {
      final councils = parseCouncils(html);
      expect(councils.length, 3);

      final adur = councils.firstWhere((c) => c.name == 'Adur');
      expect(adur.type, 'District');
      expect(adur.control, 'LAB');
      expect(adur.total, 29);
      expect(adur.seats['Lab'], 17);
      expect(adur.seats['Green'], 2);
      expect(adur.seats.containsKey('Total'), isFalse);
    });

    test('flags City of London as sui generis with independent control', () {
      final city =
          parseCouncils(html).firstWhere((c) => c.name == 'City of London');
      expect(city.type, 'Sui Generis');
      expect(city.control, 'IND');
    });

    test('skips header and totals rows', () {
      final names = parseCouncils(html).map((c) => c.name);
      expect(names, isNot(contains('Totals:')));
    });

    test('heldSeats excludes empty buckets and sorts largest first', () {
      final adur = parseCouncils(html).firstWhere((c) => c.name == 'Adur');
      expect(adur.heldSeats.map((e) => e.key), ['Lab', 'Green']);
    });
  });

  group('councilControlToken', () {
    test('maps single-party control to party tokens', () {
      expect(councilControlToken('LAB'), 'labour');
      expect(councilControlToken('CON'), 'conservative');
      expect(councilControlToken('LD'), 'libdem');
      expect(councilControlToken('GRN'), 'green');
      expect(councilControlToken('SNP'), 'snp');
      expect(councilControlToken('PC'), 'plaidcymru');
      expect(councilControlToken('REF'), 'reform');
    });

    test('colours coalitions by their leading party', () {
      expect(councilControlToken('SNP/LD'), 'snp');
      expect(councilControlToken('CON/LD/IND'), 'conservative');
    });

    test('strips minority and committee annotations', () {
      expect(councilControlToken('LABmin'), 'labour');
      expect(councilControlToken('CON(Committee)'), 'conservative');
      expect(councilControlToken('LDMayor'), 'libdem');
    });

    test('returns null for no overall control and unknown parties', () {
      expect(councilControlToken('NOC'), isNull);
      expect(councilControlToken('TBC'), isNull);
      expect(councilControlToken('CIIP'), isNull);
    });
  });

  group('controlDisplayName', () {
    test('expands codes and coalitions to friendly names', () {
      expect(controlDisplayName('LAB'), 'Labour');
      expect(controlDisplayName('SNP/LD'), 'SNP / Lib Dem');
      expect(controlDisplayName('CON/LD/IND'), 'Conservative / Lib Dem / Independent');
    });

    test('marks minorities and no overall control', () {
      expect(controlDisplayName('LABmin'), 'Labour (minority)');
      expect(controlDisplayName('NOC'), 'No overall control');
    });
  });

  group('historical parsing', () {
    test('parseHistoricalCouncils16 parses name, total, seats, and calculates control', () {
      const html16 = '''
        <table>
          <tr><td>Adur</td><td>29</td><td>
            <div class="stacked-bar-graph">
              <span class="pop con" style="width: 50%"><span class="poptext">17</span></span>
              <span class="pop lab" style="width: 50%"><span class="poptext">8</span></span>
              <span class="pop ind" style="width: 0%"><span class="poptext">4</span></span>
            </div>
          </td></tr>
        </table>
      ''';
      final councils = parseHistoricalCouncils16(html16);
      expect(councils.length, 1);
      final adur = councils.first;
      expect(adur.name, 'Adur');
      expect(adur.total, 29);
      expect(adur.seats['Con'], 17);
      expect(adur.seats['Lab'], 8);
      expect(adur.seats['Oth'], 4);
      expect(adur.control, 'CON'); // calculated majority
    });

    test('parseHistoricalCouncils73 parses name, control, total, and seats', () {
      const html73 = '''
        <table>
          <tr><td>Adur</td><td>Con</td><td>29</td><td>
            <div class="stacked-bar-graph">
              <span class="pop con" style="width: 50%"><span class="poptext">20</span></span>
              <span class="pop lab" style="width: 50%"><span class="poptext">1</span></span>
              <span class="pop ind" style="width: 0%"><span class="poptext">8</span></span>
            </div>
          </td></tr>
        </table>
      ''';
      final councils = parseHistoricalCouncils73(html73);
      expect(councils.length, 1);
      final adur = councils.first;
      expect(adur.name, 'Adur');
      expect(adur.control, 'Con'); // parsed directly
      expect(adur.total, 29);
      expect(adur.seats['Con'], 20);
      expect(adur.seats['Lab'], 1);
      expect(adur.seats['Oth'], 8);
    });

    test('parseHistoricalCouncils73 maps vac to SNP for Scottish and PC for Welsh councils', () {
      const html73 = '''
        <table>
          <tr><td>Aberdeen</td><td>NOC</td><td>43</td><td>
            <div class="stacked-bar-graph">
              <span class="pop vac" style="width: 50%"><span class="poptext">15</span></span>
            </div>
          </td></tr>
          <tr><td>Conwy</td><td>NOC</td><td>55</td><td>
            <div class="stacked-bar-graph">
              <span class="pop vac" style="width: 50%"><span class="poptext">8</span></span>
            </div>
          </td></tr>
        </table>
      ''';
      final councils = parseHistoricalCouncils73(html73);
      expect(councils.length, 2);

      final aberdeen = councils.firstWhere((c) => c.name == 'Aberdeen');
      expect(aberdeen.seats['SNP'], 15);
      expect(aberdeen.seats.containsKey('PC'), isFalse);

      final conwy = councils.firstWhere((c) => c.name == 'Conwy');
      expect(conwy.seats['PC'], 8);
      expect(conwy.seats.containsKey('SNP'), isFalse);
    });
  });
}

