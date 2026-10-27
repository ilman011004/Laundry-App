import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import '../pos/pos_repository.dart';
import 'photo_models.dart';

class PhotosRepository {
  PhotosRepository(this._dio, this._pos);

  final Dio _dio;
  final PosRepository _pos;

  Future<List<OrderPhoto>> forOrder(int orderId) async {
    final res = await _dio.get('/api/orders/$orderId/photos');
    return (res.data['data'] as List)
        .map((e) => OrderPhoto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Uint8List> bytes(int photoId) async {
    final res = await _dio.get<List<int>>(
      '/api/photos/$photoId/file',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data!);
  }

  Future<void> upload(int orderId, String path, String kind) =>
      _pos.uploadPhoto(orderId, path, kind);
}

final photosRepositoryProvider = Provider<PhotosRepository>((ref) =>
    PhotosRepository(ref.watch(dioProvider), ref.watch(posRepositoryProvider)));

final orderPhotosProvider =
    FutureProvider.autoDispose.family<List<OrderPhoto>, int>((ref, orderId) {
  return ref.watch(photosRepositoryProvider).forOrder(orderId);
});

final photoBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, int>((ref, photoId) {
  return ref.watch(photosRepositoryProvider).bytes(photoId);
});