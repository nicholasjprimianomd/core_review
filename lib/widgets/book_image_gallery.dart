import 'package:flutter/material.dart';

import '../config/app_config.dart';

class BookImageGallery extends StatelessWidget {
  const BookImageGallery({required this.imageAssets, super.key});

  final List<String> imageAssets;

  @override
  Widget build(BuildContext context) {
    if (imageAssets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          imageAssets.length == 1 ? 'Image' : 'Images',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < imageAssets.length; index++) ...[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: InkWell(
                onTap: () => _showFullscreenGallery(context, index),
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildImage(imageAssets[index]),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  void _showFullscreenGallery(BuildContext context, int initialIndex) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          child: _FullscreenImageGallery(
            imageAssets: imageAssets,
            initialIndex: initialIndex,
          ),
        );
      },
    );
  }

  Widget _buildImage(String imagePath) {
    final remoteUrl = AppConfig.resolveRemoteContentUrl(imagePath);
    if (remoteUrl != null) {
      return Image.network(
        remoteUrl,
        width: double.infinity,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('Unable to load this image.'),
            ),
          );
        },
      );
    }

    return Image.asset(
      imagePath,
      width: double.infinity,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Unable to load this image asset.'),
          ),
        );
      },
    );
  }
}

class _FullscreenImageGallery extends StatefulWidget {
  const _FullscreenImageGallery({
    required this.imageAssets,
    required this.initialIndex,
  });

  final List<String> imageAssets;
  final int initialIndex;

  @override
  State<_FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<_FullscreenImageGallery> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _currentIndex = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Image ${_currentIndex + 1} of ${widget.imageAssets.length}',
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageAssets.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final remoteUrl = AppConfig.resolveRemoteContentUrl(
            widget.imageAssets[index],
          );
          return InteractiveViewer(
            minScale: 0.75,
            maxScale: 5,
            child: Center(
              child: remoteUrl != null
                  ? Image.network(
                      remoteUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('Unable to load this image.'),
                          ),
                        );
                      },
                    )
                  : Image.asset(
                      widget.imageAssets[index],
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('Unable to load this image asset.'),
                          ),
                        );
                      },
                    ),
            ),
          );
        },
      ),
    );
  }
}
