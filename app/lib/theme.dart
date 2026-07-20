import 'package:flutter/material.dart';

// Dark surfaces tuned to match modern chatbot UIs (sidebar darker than the
// conversation pane, cards/input one step lighter). Shared across screens
// so the chat UI and the model detail page stay visually consistent.
const sidebarColor = Color(0xFF0F1014);
const mainColor = Color(0xFF17181F);
const cardColor = Color(0xFF23252F);
const borderColor = Color(0x14FFFFFF);

// Hardware-fit badge colours (see ModelFitRating). Desaturated against these
// dark surfaces so a wall of model cards doesn't turn into a traffic light —
// and paired with a text label everywhere they appear, since colour alone
// isn't readable for colour-blind users.
const fitOptimalColor = Color(0xFF4ADE80);
const fitPossibleColor = Color(0xFFFACC15);
const fitNotRecommendedColor = Color(0xFFF87171);
const fitUnknownColor = Color(0xFF8A8F9C);
