#include "StyleTokensBackend.h"

#include <Qt>

namespace {
QColor hex(const char *value)
{
    return QColor(QString::fromLatin1(value));
}
}

#define STYLE_COLOR(name, value) \
    QColor StyleTokensBackend::name() const \
    { \
        static const QColor color = hex(value); \
        return color; \
    }

#define STYLE_GLOBAL_COLOR(name, value) \
    QColor StyleTokensBackend::name() const \
    { \
        return value; \
    }

StyleTokensBackend::StyleTokensBackend(QObject *parent)
    : QObject(parent)
{
}

STYLE_GLOBAL_COLOR(transparent, Qt::transparent)
STYLE_GLOBAL_COLOR(black, Qt::black)
STYLE_GLOBAL_COLOR(white, Qt::white)
QColor StyleTokensBackend::clearBlack() const { return QColor(0, 0, 0, 0); }
STYLE_COLOR(panel, "#121315")
STYLE_COLOR(module, "#0a0b0d")
STYLE_COLOR(moduleHover, "#17191c")
STYLE_COLOR(track, "#2a2d31")
STYLE_COLOR(cardFillActive, "#17191c")
STYLE_COLOR(cardFillHover, "#202328")
STYLE_COLOR(connectivityCard, "#131519")
STYLE_COLOR(connectivityCardHover, "#1b1e23")
STYLE_COLOR(prompt, "#16181c")
STYLE_COLOR(input, "#0c0d10")
STYLE_COLOR(inputBorder, "#343841")
STYLE_COLOR(secondaryButton, "#1e2126")
STYLE_COLOR(textPrimary, "#f1f3f5")
STYLE_COLOR(textPrimaryBright, "#ffffff")
STYLE_COLOR(textSecondary, "#d2d6dc")
STYLE_COLOR(textMuted, "#a4abb4")
STYLE_COLOR(textSoft, "#8d949d")
STYLE_COLOR(textTertiary, "#7c848d")
STYLE_COLOR(textDisabled, "#666d76")
STYLE_COLOR(textSubtle, "#c3c8cf")
STYLE_COLOR(textDim, "#8e959e")
STYLE_COLOR(accent, "#7f8a96")
STYLE_COLOR(accentPressed, "#4a515a")
STYLE_COLOR(accentSoft, "#a1aab4")
STYLE_COLOR(success, "#7ca08c")
STYLE_COLOR(warning, "#b49a6a")
STYLE_COLOR(danger, "#8f6d76")
STYLE_COLOR(error, "#b18490")
STYLE_COLOR(disabledControl, "#555b63")
STYLE_COLOR(switchOff, "#4a4f56")
STYLE_COLOR(buttonFill, "#7f8a96")
STYLE_COLOR(buttonFillHover, "#98a3ae")
STYLE_COLOR(buttonFillPressed, "#5c6670")
STYLE_COLOR(overviewCard, "#131518")
STYLE_COLOR(overviewBorder, "#667f8a96")
STYLE_COLOR(overviewInnerBorder, "#267f8a96")
STYLE_COLOR(workspaceCell, "#111317")
STYLE_COLOR(workspaceCellHover, "#1a1d22")
STYLE_COLOR(workspaceCellBorder, "#337f8a96")
STYLE_COLOR(workspaceCellBorderHover, "#66a1aab4")
STYLE_COLOR(workspaceOverlay, "#107f8a96")
STYLE_COLOR(workspaceOverlayHover, "#18a1aab4")
STYLE_COLOR(workspaceActiveBorder, "#a1aab4")

int StyleTokensBackend::radiusPanel() const { return 999; }
int StyleTokensBackend::radiusModule() const { return 999; }
int StyleTokensBackend::radiusPrompt() const { return 20; }
int StyleTokensBackend::radiusButton() const { return 999; }
int StyleTokensBackend::durationFast() const { return 120; }
int StyleTokensBackend::durationControl() const { return 130; }
int StyleTokensBackend::durationQuick() const { return 140; }
int StyleTokensBackend::durationStandard() const { return 280; }

#undef STYLE_COLOR
#undef STYLE_GLOBAL_COLOR
