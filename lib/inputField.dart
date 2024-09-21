import 'package:flutter/material.dart';

class InputField extends StatelessWidget {
  final String label;
  final bool isPassword;
  final int minLines;
  final String helperText;
  final TextEditingController? controller; // Add controller parameter
  final ValueChanged<String>? onChanged; // Add onChanged parameter

  const InputField({
    Key? key,
    required this.label,
    this.helperText = "",
    this.isPassword = false,
    this.minLines = 1,
    this.controller, // Initialize controller
    this.onChanged, // Initialize onChanged
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller, // Use the controller here
          obscureText: isPassword,
          maxLines: isPassword ? 1 : null, // Allow unlimited lines
          minLines: minLines, // Minimum lines to show
          onChanged: onChanged, // Use the onChanged function here
          decoration: InputDecoration(
            hintText: helperText, // 添加 placeholder
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: Colors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        SizedBox(height: 4),
      ],
    );
  }
}
