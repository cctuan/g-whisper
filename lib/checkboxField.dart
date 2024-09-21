import 'package:flutter/material.dart';

class CheckboxField extends StatefulWidget {
  final String label;
  final String description;
  final bool initialValue;
  final ValueChanged<bool?> onChanged;

  const CheckboxField({
    Key? key,
    required this.label,
    this.description = "",
    this.initialValue = false,
    required this.onChanged,
  }) : super(key: key);

  @override
  _CheckboxFieldState createState() => _CheckboxFieldState();
}

class _CheckboxFieldState extends State<CheckboxField> {
  late bool _isChecked;

  @override
  void initState() {
    super.initState();
    _isChecked = widget.initialValue; // 初始化狀態
  }

  @override
  void didUpdateWidget(CheckboxField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setState(() {
        _isChecked = widget.initialValue; // 更新狀態
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(height: 4),
        Text(
          widget.label,
          style: TextStyle(
              color: Color(0xFF27292A),
              fontSize: 13,
              fontWeight: FontWeight.w500),
        ),
        SizedBox(width: 8),
        Expanded(
            child: Row(
          children: [
            Checkbox(
              value: _isChecked,
              onChanged: (bool? value) {
                setState(() {
                  _isChecked = value ?? false; // 更新狀態
                });
                widget.onChanged(value); // 通知父組件
              },
            ),
            SizedBox(width: 4),
            Expanded(
              child: Text(widget.description,
                  style: TextStyle(
                    color: Color(0xFF27292A),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  )),
            )
          ],
        )),
        SizedBox(height: 4),
      ],
    );
  }
}
