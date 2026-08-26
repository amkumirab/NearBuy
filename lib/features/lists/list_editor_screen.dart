import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as osm;
import 'package:nearbuy/core/repositories/nearbuy_repository.dart';
import 'package:nearbuy/features/map/location_picker_screen.dart';
import 'package:nearbuy/providers.dart';

class ListEditorScreen extends ConsumerStatefulWidget {
  const ListEditorScreen({super.key, this.listId});

  final String? listId;

  @override
  ConsumerState<ListEditorScreen> createState() => _ListEditorScreenState();
}

class _ListEditorScreenState extends ConsumerState<ListEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final List<_DraftItemFields> _draftItems = [_DraftItemFields()];

  bool _loading = true;
  bool _saving = false;
  bool _hasLocation = false;
  bool _geofenceEnabled = true;
  String _category = 'Supermarket';
  int _radius = 700;
  osm.LatLng? _selectedLocation;

  static const _categories = [
    'Supermarket',
    'Pharmacy',
    'Electronics',
    'Clothing',
    'Bakery',
    'Hardware',
    'Other',
  ];
  static const _radii = [250, 500, 700, 1000, 2000];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(repositoryProvider);
    final settings = await repository.readSettings();
    _radius = settings.defaultRadius;
    if (widget.listId != null) {
      final list = await repository.findList(widget.listId!);
      if (list != null) {
        _name.text = list.name;
        if (list.storeId != null) {
          final store = await repository.findStore(list.storeId!);
          if (store != null) {
            _hasLocation = true;
            _geofenceEnabled = store.geofenceEnabled;
            _category = store.category;
            _radius = store.geofenceRadius;
            _address.text = store.address;
            _setLocation(osm.LatLng(store.latitude, store.longitude));
          }
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setLocation(osm.LatLng value) {
    _selectedLocation = value;
    _latitude.text = value.latitude.toStringAsFixed(6);
    _longitude.text = value.longitude.toStringAsFixed(6);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    for (final item in _draftItems) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.listId == null ? 'New shopping list' : 'Edit list',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                const _SectionTitle(
                  icon: Icons.list_alt_rounded,
                  title: 'List details',
                ),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'List or store name',
                    hintText: 'e.g. Lidl',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a list name'
                      : null,
                ),
                const SizedBox(height: 18),
                Card(
                  child: SwitchListTile(
                    value: _hasLocation,
                    onChanged: (value) => setState(() => _hasLocation = value),
                    secondary: const Icon(Icons.add_location_alt_outlined),
                    title: const Text(
                      'Link a physical store',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      'Optional. Required only for proximity reminders.',
                    ),
                  ),
                ),
                if (_hasLocation) ...[
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    icon: Icons.storefront_outlined,
                    title: 'Store & reminder',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _address,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Address or store note (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openLocationPicker,
                      icon: const Icon(Icons.map_rounded),
                      label: Text(
                        _selectedLocation == null
                            ? 'Choose location on map'
                            : 'Change location on map',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  if (_selectedLocation != null) ...[
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.place_rounded),
                        title: Text(
                          _address.text.trim().isEmpty
                              ? 'Selected store location'
                              : _address.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Clear selected location',
                          onPressed: () => setState(() {
                            _selectedLocation = null;
                            _address.clear();
                            _latitude.clear();
                            _longitude.clear();
                          }),
                          icon: const Icon(Icons.clear_rounded),
                        ),
                        onTap: _openLocationPicker,
                      ),
                    ),
                  ],
                  Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.pin_drop_outlined),
                      title: const Text('Enter coordinates manually'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _latitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Latitude',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _longitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Longitude',
                                ),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _applyManualCoordinates,
                            child: const Text('Apply coordinates'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Reminder radius · ${_radius >= 1000 ? '${_radius ~/ 1000} km' : '$_radius m'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _radii
                        .map(
                          (value) => ChoiceChip(
                            label: Text(
                              value >= 1000
                                  ? '${value ~/ 1000} km'
                                  : '$value m',
                            ),
                            selected: _radius == value,
                            onSelected: (_) => setState(() => _radius = value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _geofenceEnabled,
                    onChanged: (value) =>
                        setState(() => _geofenceEnabled = value),
                    title: const Text(
                      'Enable proximity reminders',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                if (widget.listId == null) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: _SectionTitle(
                          icon: Icons.playlist_add_rounded,
                          title: 'Initial items',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _draftItems.add(_DraftItemFields())),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add row'),
                      ),
                    ],
                  ),
                  ..._draftItems.indexed.map((entry) {
                    final index = entry.$1;
                    final item = entry.$2;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: item.name,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      decoration: InputDecoration(
                                        labelText: 'Item ${index + 1}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 90,
                                    child: TextField(
                                      controller: item.quantity,
                                      decoration: const InputDecoration(
                                        labelText: 'Qty',
                                      ),
                                    ),
                                  ),
                                  if (_draftItems.length > 1)
                                    IconButton(
                                      tooltip: 'Remove row',
                                      onPressed: () => setState(() {
                                        _draftItems.removeAt(index).dispose();
                                      }),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: item.note,
                                decoration: const InputDecoration(
                                  labelText: 'Note (optional)',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton.icon(
        onPressed: _saving || _loading ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded),
        label: Text(
          widget.listId == null ? 'Create shopping list' : 'Save changes',
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    ),
  );

  void _applyManualCoordinates() {
    final lat = double.tryParse(_latitude.text.trim());
    final lng = double.tryParse(_longitude.text.trim());
    if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid latitude and longitude values.'),
        ),
      );
      return;
    }
    setState(() => _setLocation(osm.LatLng(lat, lng)));
  }

  Future<void> _openLocationPicker() async {
    final selection = await Navigator.of(context).push<LocationSelection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerScreen(
          initialPosition: _selectedLocation,
          initialAddress: _address.text.trim(),
        ),
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _setLocation(selection.position);
      if (selection.address.isNotEmpty) _address.text = selection.address;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasLocation && _selectedLocation == null) {
      _applyManualCoordinates();
      if (_selectedLocation == null) return;
    }
    setState(() => _saving = true);
    try {
      final store = !_hasLocation
          ? null
          : StoreDraft(
              name: _name.text.trim(),
              category: _category,
              latitude: _selectedLocation!.latitude,
              longitude: _selectedLocation!.longitude,
              address: _address.text.trim(),
              geofenceRadius: _radius,
              geofenceEnabled: _geofenceEnabled,
            );
      final id = await ref
          .read(actionsProvider)
          .saveList(
            listId: widget.listId,
            name: _name.text,
            store: store,
            items: widget.listId == null
                ? _draftItems
                      .where((item) => item.name.text.trim().isNotEmpty)
                      .map(
                        (item) => ItemDraft(
                          name: item.name.text,
                          quantity: item.quantity.text,
                          note: item.note.text,
                        ),
                      )
                      .toList()
                : const [],
          );
      if (mounted) {
        context.go('/lists/$id');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the list: $error')),
        );
        setState(() => _saving = false);
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _DraftItemFields {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final note = TextEditingController();

  void dispose() {
    name.dispose();
    quantity.dispose();
    note.dispose();
  }
}
