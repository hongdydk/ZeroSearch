import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/address/daum_postcode_bridge.dart';
import '../../core/models/models.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/async_busy.dart';
import '../../shared/widgets/page_form_scaffold.dart';

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, this.addressId});

  final String? addressId;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen>
    with AsyncBusyState {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _zonecode = TextEditingController();
  final _address = TextEditingController();
  final _detail = TextEditingController();
  bool _isDefault = false;
  bool _hydrated = false;

  bool get _editing => widget.addressId != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _zonecode.dispose();
    _address.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _fill(ShippingAddressModel address) {
    _name.text = address.recipientName;
    _phone.text = address.phone;
    _zonecode.text = address.zonecode;
    _address.text = address.address;
    _detail.text = address.detailAddress;
    _isDefault = address.isDefault;
  }

  Future<void> _searchPostcode() async {
    try {
      final result = await requestDaumPostcode();
      if (result == null || !mounted) return;
      setState(() {
        _zonecode.text = result.zonecode;
        _address.text = result.address;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is StateError ? e.message : '주소 검색을 열지 못했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await runBusy('address-save', () async {
      try {
        final api = ref.read(apiClientProvider);
        if (_editing) {
          await api.updateAddress(
            widget.addressId!,
            recipientName: _name.text.trim(),
            phone: _phone.text.trim(),
            zonecode: _zonecode.text.trim(),
            address: _address.text.trim(),
            detailAddress: _detail.text.trim(),
            isDefault: _isDefault,
          );
        } else {
          await api.createAddress(
            recipientName: _name.text.trim(),
            phone: _phone.text.trim(),
            zonecode: _zonecode.text.trim(),
            address: _address.text.trim(),
            detailAddress: _detail.text.trim(),
            isDefault: _isDefault,
          );
        }
        ref.invalidate(addressesProvider);
        if (!mounted) return;
        context.pop();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_editing && !_hydrated) {
      final addresses = ref.watch(addressesProvider).valueOrNull;
      if (addresses != null) {
        final found = addresses.where((e) => e.id == widget.addressId);
        if (found.isNotEmpty) {
          _fill(found.first);
          _hydrated = true;
        }
      }
    }

    final lookupReadOnly = daumPostcodeSupported;

    return PageFormScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing ? '배송지 수정' : '배송지 추가',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '받는 분'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '받는 분을 입력해 주세요.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: '휴대폰'),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                final digits = value?.trim() ?? '';
                if (digits.length < 8 || digits.length > 15) {
                  return '휴대폰 번호는 숫자 8~15자리여야 합니다.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _zonecode,
                    readOnly: lookupReadOnly,
                    decoration: const InputDecoration(labelText: '우편번호'),
                    keyboardType: TextInputType.number,
                    validator: (value) => (value == null || value.trim().length < 4)
                        ? '우편번호를 입력해 주세요.'
                        : null,
                  ),
                ),
                if (daumPostcodeSupported) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: isBusy() ? null : _searchPostcode,
                      child: const Text('주소 찾기'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              readOnly: lookupReadOnly,
              decoration: const InputDecoration(labelText: '주소'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '주소를 입력해 주세요.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _detail,
              decoration: const InputDecoration(labelText: '상세주소'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '상세주소를 입력해 주세요.' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('기본 배송지로 저장'),
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isBusy() ? null : _save,
              child: Text(isBusy() ? '저장 중…' : '저장'),
            ),
          ],
        ),
      ),
    );
  }
}
