import 'package:dating_app/constants/constants.dart';
import 'package:dating_app/helpers/app_localizations.dart';
import 'package:dating_app/models/user_model.dart';
import 'package:flutter/material.dart';

class HideProfileDialog extends StatefulWidget {
  const HideProfileDialog({Key? key}) : super(key: key);

  @override
  _HideProfileDialogState createState() => _HideProfileDialogState();
}

class _HideProfileDialogState extends State<HideProfileDialog> {
  // Variables
  final Map<String, dynamic>? _userSettings = UserModel().user.userSettings;
  String _selectedOption = "";
  String _selectedOptionKey = "";
  String _selectedOptionvalue = "";
  int selectedTime = 0;
  late AppLocalizations _i18n;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Variables
    final String? showMe = _userSettings?[USER_Hide_Time];
    // Check option
    if (showMe != null) {
      setState(() {
        _selectedOption =showMe;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialization
    _i18n = AppLocalizations.of(context);
    // Map options
    final Map<String, String> mapOptions = {
      "12": "12hr",
      "24": "24hr",
      "48": "48hr",
      "0": "Select Time",
    };

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: _dialogContent(context, mapOptions),
      elevation: 3,
    );
  }

// Build dialog
  Widget _dialogContent(BuildContext context, Map<String, String> mapOptions) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.wc),
              const SizedBox(width: 5),
              Text(
                _i18n.translate("show_me"),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
        const Divider(
          color: Colors.black,
          height: 5,
        ),
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: mapOptions.entries.map((option) {
                  return RadioListTile<String>(
                      selected: _selectedOption == option.value ? true : false,
                      title: Text(option.value),
                      activeColor: Theme.of(context).primaryColor,
                      value: option.value,
                      groupValue: _selectedOption,
                      onChanged: (value) {
                        setState(() {
                          _selectedOption = value.toString();
                          _selectedOptionKey = option.key;
                          _selectedOptionvalue = option.value;
                          int val = int.parse(_selectedOptionKey);
                          // selectedTime = val *60*60;
                          selectedTime = val *60*60;
                         });
                        debugPrint('Selected option: $value');
                      });
                }).toList()),
          ),
        ),
        const Divider(
          color: Colors.black,
          height: 5,
        ),
        Builder(
          builder: (context) {
            return Padding(
              padding: const EdgeInsets.all(5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    child: Text(_i18n.translate("CANCEL")),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: Text(_i18n.translate("SAVE"),
                        style:
                        TextStyle(color: Theme.of(context).primaryColor)),
                    onPressed: _selectedOption == ''
                        ? null
                        : () async {
                      /// Save option
                      DateTime secondTime = DateTime.now().add( Duration(seconds: selectedTime));

                      await UserModel().updateUserData(
                          userId: UserModel().user.userId,
                          data: {
                            USER_Hide_Profile_Time:
                            "${secondTime}",
                            '$USER_SETTINGS.$USER_Hide_Time':
                            _selectedOptionvalue

                          });

                      // Close dialog
                      Navigator.of(context).pop();
                      debugPrint('Show me option() -> saved');
                    },
                  ),
                ],
              ),
            );
          },
        )
      ],
    );
  }
/*  void checktime({required String time}){

    if(time =="12"){
      selectedTime =
      value ="43200";
    }else if(time =="24"){
      value ="86400";
    }else if(time =="48"){
      value ="172800";
    }else{
      value ="1";
    }
    return value;

  }*/
}