import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flame/providers/story_provider.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

/// Create a photo story: pick from camera/gallery → optional caption → post.
/// No editing studio (photos-only, lean slice).
class CreateStoryScreen extends ConsumerStatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  final _picker = ImagePicker();
  final _captionController = TextEditingController();
  File? _image;
  bool _posting = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _image = File(picked.path));
    }
  }

  Future<void> _post() async {
    final image = _image;
    if (image == null || _posting) return;
    setState(() => _posting = true);
    final story = await ref.read(storyActionsProvider).create(
          image: image,
          caption: _captionController.text.trim().isEmpty
              ? null
              : _captionController.text.trim(),
        );
    if (!mounted) return;
    if (story != null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.storyUploadFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.storyAdd)),
      body: _image == null ? _buildPicker(context) : _buildPreview(context),
    );
  }

  Widget _buildPicker(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              text: context.l10n.storyPickCamera,
              icon: Icons.photo_camera_outlined,
              isFullWidth: true,
              onPressed: () => _pick(ImageSource.camera),
            ),
            const SizedBox(height: 12),
            AppButton(
              text: context.l10n.storyPickGallery,
              icon: Icons.photo_library_outlined,
              variant: AppButtonVariant.outline,
              isFullWidth: true,
              onPressed: () => _pick(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: Image.file(_image!, fit: BoxFit.contain),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            children: [
              AppInput(
                controller: _captionController,
                hint: context.l10n.storyCaptionHint,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              AppButton(
                text: context.l10n.storyPost,
                isFullWidth: true,
                isLoading: _posting,
                onPressed: _post,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
