import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/portal_workspace.dart';

class AdminSellerDirectoryScreen extends ConsumerStatefulWidget { const AdminSellerDirectoryScreen({super.key}); @override ConsumerState<AdminSellerDirectoryScreen> createState()=>_AdminSellerDirectoryScreenState(); }
class _AdminSellerDirectoryScreenState extends ConsumerState<AdminSellerDirectoryScreen> {
 final _search=TextEditingController(); List<AdminSellerModel> _items=[]; var _total=0; var _offset=0; var _status=''; var _loading=true; Timer? _timer;
 @override void initState(){super.initState();_load();}
 @override void dispose(){_timer?.cancel();_search.dispose();super.dispose();}
 Future<void> _load({int? offset}) async { setState(()=>_loading=true); final page=await ref.read(apiClientProvider).adminSellerPage(q:_search.text.trim(),status:_status,offset:offset??_offset); if(mounted)setState((){_items=page.items;_total=page.total;_offset=page.offset;_loading=false;}); }
 @override Widget build(BuildContext context)=>PortalWorkspaceScaffold(role:PortalWorkspaceRole.admin,activePath:'/admin/sellers',child:PortalPage(eyebrow:'관리자',title:'입점 관리',child:Column(children:[TextField(controller:_search,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'상호, 이메일, 스토어 주소 검색'),onChanged:(_){_timer?.cancel();_timer=Timer(const Duration(milliseconds:300),()=>_load(offset:0));}),const SizedBox(height:8),Wrap(spacing:8,children:[for(final row in const [('','전체'),('pending','승인 대기'),('active','운영'),('suspended','정지'),('removed','해제')]) ChoiceChip(label:Text(row.$2),selected:_status==row.$1,onSelected:(_){setState(()=>_status=row.$1);_load(offset:0);})]),const SizedBox(height:12),if(_loading)const LinearProgressIndicator(),Text('총 $_total곳'),for(final seller in _items) Card(child:ListTile(onTap:()=>context.push('/stores/${seller.slug}'),leading:const Icon(Icons.storefront_outlined),title:Text(seller.shopName),subtitle:Text('${seller.userEmail}\n공개 ${seller.publishedOfferCount} · 품절 ${seller.soldOutOfferCount} · 숨김 ${seller.hiddenOfferCount}${seller.pendingDraftCount>0?' · 제안 ${seller.pendingDraftCount}':''}'),isThreeLine:true,trailing:const Icon(Icons.arrow_outward))),Row(mainAxisAlignment:MainAxisAlignment.end,children:[TextButton(onPressed:_offset==0?null:()=>_load(offset:_offset-30),child:const Text('이전')),TextButton(onPressed:_offset+30>=_total?null:()=>_load(offset:_offset+30),child:const Text('다음'))])])));
}
