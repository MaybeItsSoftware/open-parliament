import 'package:flutter/material.dart';

import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/party_colors.dart' as party_util;
import '../utils/seat_layout.dart';

enum HouseType { commons, lords }

class SeatingSeat {
  final Member member;
  final Offset position;
  final Color color;

  const SeatingSeat({
    required this.member,
    required this.position,
    required this.color,
  });
}

class PartyBreakdown {
  final String label;
  final int count;
  final Color color;

  const PartyBreakdown({
    required this.label,
    required this.count,
    required this.color,
  });
}

class HouseSeatingViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  bool _isLoading = false;
  String? _error;
  HouseType _house = HouseType.commons;
  final Map<HouseType, List<SeatingSeat>> _seatsByHouse = {};
  final Map<HouseType, List<PartyBreakdown>> _breakdownsByHouse = {};
  final Map<HouseType, int> _totalsByHouse = {};

  HouseSeatingViewModel(this._service);

  bool get isLoading => _isLoading;
  String? get error => _error;
  HouseType get house => _house;
  List<SeatingSeat> get seats => _seatsByHouse[_house] ?? const [];
  List<PartyBreakdown> get breakdown =>
      _breakdownsByHouse[_house] ?? const [];
  int get totalMembers => _totalsByHouse[_house] ?? 0;

  Future<void> load(HouseType house) async {
    _house = house;
    if (_seatsByHouse.containsKey(house)) {
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final members = await _service.getMembers();
      final filtered = [
        for (final m in members)
          if (_matchesHouse(m, house)) m,
      ];

      final groups = _groupByParty(filtered);
      final orderedMembers = <Member>[
        for (final group in groups) ...group.members,
      ];

      final positions = buildChamberLayout(house: house, members: orderedMembers);
      final seats = <SeatingSeat>[
        for (var i = 0; i < orderedMembers.length; i++)
          SeatingSeat(
            member: orderedMembers[i],
            position: positions[i],
            color: party_util.partyColor(_partyKey(orderedMembers[i])),
          ),
      ];

      _seatsByHouse[house] = seats;
      _breakdownsByHouse[house] = [
        for (final group in groups)
          PartyBreakdown(
            label: group.label,
            count: group.members.length,
            color: group.color,
          ),
      ];
      _totalsByHouse[house] = orderedMembers.length;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _seatsByHouse.clear();
    _breakdownsByHouse.clear();
    _totalsByHouse.clear();
    await load(_house);
  }

  bool _matchesHouse(Member member, HouseType house) {
    return house == HouseType.commons
        ? member.constituency.isNotEmpty
        : member.constituency.isEmpty;
  }

  List<_PartyGroup> _groupByParty(List<Member> members) {
    final groups = <String, _PartyGroup>{};
    for (final member in members) {
      final label = _partyLabel(member);
      final token =
          party_util.canonicalPartyToken(_partyKey(member)) ?? label.toLowerCase();
      final color = party_util.partyColor(token);
      final group =
          groups.putIfAbsent(token, () => _PartyGroup(token, label, color));
      group.members.add(member);
    }

    final list = groups.values.toList();
    list.sort((a, b) {
      final count = b.members.length.compareTo(a.members.length);
      if (count != 0) return count;
      return a.label.compareTo(b.label);
    });

    for (final group in list) {
      group.members.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  String _partyKey(Member member) {
    if (member.partyAbbreviation.isNotEmpty) return member.partyAbbreviation;
    if (member.party.isNotEmpty) return member.party;
    return 'Independent';
  }

  String _partyLabel(Member member) {
    if (member.party.isNotEmpty) return member.party;
    if (member.partyAbbreviation.isNotEmpty) return member.partyAbbreviation;
    return 'Independent';
  }
}

class _PartyGroup {
  final String token;
  final String label;
  final Color color;
  final List<Member> members = [];

  _PartyGroup(this.token, this.label, this.color);
}
