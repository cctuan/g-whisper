import 'package:flutter/material.dart';

class Sidebar extends StatefulWidget {
  final Function(String) onItemSelected;

  const Sidebar({Key? key, required this.onItemSelected}) : super(key: key);

  @override
  _SidebarState createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String? selectedItem = 'General'; // Initialize with 'General'

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      // color: const Color(0xFFF5F5F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebarItem('General'),
          _buildSidebarItem('STT Options'),
          _buildSidebarItem('LLM Options'),
          _buildSidebarItem('File Settings'),
          _buildSidebarItem('Wiki Settings'),
          _buildSidebarItem('Prompt Settings'),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(String title) {
    final isSelected = title == selectedItem; // Check if the item is selected
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedItem = title; // Update selected item
        });
        widget
            .onItemSelected(title); // Call the callback with the selected title
      },
      child: Container(
        width: double.infinity,
        // Wrap in Container for background color
        color: isSelected
            ? const Color(0xFFE0E0E0)
            : Colors.transparent, // Change background color if selected
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: 'SF Pro Text',
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color:
                isSelected ? const Color(0xFF0F66DE) : const Color(0xFF27292A),
          ),
        ),
      ),
    );
  }
}
