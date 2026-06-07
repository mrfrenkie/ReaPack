-- @noindex

-- Frenkie Recent Projects - Theme Definition

FRPTheme = {
    name = "Default Dark",
    description = "Default dark theme for Frenkie Recent Projects UI.",

    colors = {
        text_muted = 0x5F5F5FFF,                 -- Muted gray text for secondary labels and hints
        text = 0x1F1F1FFF,                       -- Primary light text for main content
        text_black = 0xFFFFFFFF,                 -- Solid black text for bright backgrounds
        text_inverted = 0x000000FF,              -- Solid white text for dark accent and badges

        accent = 0xD95965FF,                     -- Main accent color for highlights and active elements

        bg_window = 0xD8D8D8FF,                  -- Main window background
        bg_title = 0xC8C8C8FF,                   -- Title bar background (inactive)
        bg_title_active = 0xB8B8B8FF,            -- Title bar background (active window)

        frame_bg = 0xC5C5C5FF,                   -- Generic frame background (inputs, boxes)
        frame_bg_hovered = 0xB5B5B5FF,           -- Frame background when hovered
        frame_bg_active = 0xA5A5A5FF,            -- Frame background when pressed or active

        button_bg = 0xB5B5B5FF,                  -- Default button background
        button_bg_hover = 0xA5A5A5FF,            -- Button hover background
        button_bg_active = 0x979797FF,           -- Button background when pressed
        button_disabled_bg = 0xD0D0D0FF,         -- Button background when disabled

        black_transparent = 0x00000000,          -- Fully transparent black (no fill)
        black_bg_very_soft = 0x00000010,         -- Very soft black overlay (subtle panels)
        black_bg_soft = 0x00000022,              -- Soft black overlay (row striping, hover fills)
        black_bg_medium = 0x00000033,            -- Medium black overlay (selected rows)
        black_line_soft = 0x00000040,            -- Soft black line for subtle separators
        black_bg_strong = 0x00000044,            -- Strong black overlay (emphasis, overlays)
        black_bg_overlay = 0x00000080,           -- Dark overlay for modal and focus states
        black_bg_tip = 0x000000A0,               -- Dark tooltip background behind highlighted text

        white_highlight = 0xFFFFFF66,            -- Warm white highlight for timeline region labels
        white_line = 0xFFFFFF26,                 -- Soft white line for separators
        white_line_weak = 0xFFFFFF22,            -- Very subtle white line for gentle separators

        table_row_bg = 0x00000000,               -- Default table row background (transparent)
        table_row_bg_alt = 0x00000022,           -- Alternate row background for striping
        table_empty_bg = 0x00000088,

        border = 0xA0A0A0FF,                     -- General border color for windows and tables
        popup_bg = 0xD4D4D4FF,                   -- Popup background (context menus)
        dark_30 = 0xB0B0B0FF,                    -- Utility dark gray for generic lines and fills

        header_hover = 0xA0A0A040,               -- Table header background when hovered
        header_active = 0x90909060,              -- Table header background when pressed

        border_shadow = 0x00000080,              -- Shadow color for borders and outlines

        scrollbar_bg = 0x00000010,               -- Scrollbar track background
        scrollbar_grab = 0x55555540,             -- Scrollbar handle (idle)
        scrollbar_grab_hovered = 0x45454570,     -- Scrollbar handle when hovered
        scrollbar_grab_active = 0x35353590,      -- Scrollbar handle while dragging

        resize_grip = 0xA0A0A080,                -- Resize grip idle color
        resize_grip_hovered = 0x808080C0,        -- Resize grip when hovered
        resize_grip_active = 0x606060FF,         -- Resize grip when actively dragged

        close_button_base = 0x66CCCCFF,          -- Mac-style close button base color
        close_button_hover = 0x44BBBBFF,         -- Mac-style close button when hovered
        close_button_active = 0x88DDDDFF,        -- Mac-style close button when pressed
        close_button_cross = 0x000000FF,         -- Cross icon inside the close button

        border_highlight_rect = 0x6F6F6F80,      -- Border around highlighted or focused items
        toggle_hover_fill = 0xD1D1D1FF,          -- Toggle button hover fill in compact header

        tooltip_bg = 0x5F5F5FD9,                 -- Background for styled tooltips
        tooltip_border = 0x00000000,             -- Tooltip border (transparent to keep it soft)
        tooltip_text = 0xFFFFFFFF,               -- Tooltip text color

        timeline_bg_enabled = 0xBEBEBE80,        -- Timeline background when enabled
        timeline_bg_disabled = 0xBEBEBECC,       -- Timeline background when disabled
        timeline_playbar_fill = 0xD9596560,      -- Preview position fill inside timeline
        timeline_region_separator = 0x00000066,  -- Vertical separator for regions in timeline
        timeline_region_separator_soft = 0x00000022, -- Soft separator line in timeline overlays

        meta_text_secondary = 0x6F6F6FFF,        -- Secondary meta text under project name
        project_missing_text = 0x00BFBFFF,       -- Text color for missing or unavailable projects

        search_placeholder = 0x7F7F7FAA,         -- Placeholder text in the search field

        inline_toggle_bg = 0xD0D0D080,           -- Inline toggle background (on/off style)
        inline_bg_selected = 0xB0B0B0AA,         -- Background for selected inline controls
        inline_bg_fill = 0x00000033,             -- Inline background behind preview count
        inline_border_light = 0xA0A0A080,        -- Light border line in inline area
        inline_border_dark = 0x00000040,         -- Dark border line in inline area

        meta_panel_bg = 0xDCDCDCFF,
        toolbar_button_bg = 0xC4C4C4FF,
        toolbar_button_active = 0xA8A8A8FF,
        toolbar_compact_button_bg = 0x505050FF,
        toolbar_compact_button_hover = 0x424242FF,
        toolbar_compact_button_active = 0x5C5C5CFF,

        row_bg_selected = 0x00000080,            -- Background for selected rows
        row_bg_pinned = 0x00000044,              -- Background for pinned rows
        row_bg_hover = 0x90909040,               -- Row hover overlay
        row_bg_focus = 0x80808020,               -- Focus or keyboard-selected row overlay
        row_bg_hover_soft = 0xA0A0A020,          -- Soft hover overlay for subtle feedback

        slider_grab_active = 0x141414FF,         -- Active slider grab handle

        bottom_line_separator = 0xA0A0A066,      -- Separator line above the footer

        footer_text_muted = 0x5F5F5FFF,          -- Muted footer text (version and author)

        footer_popup_bg = 0xD0D0D0F0,            -- Background for footer popup (about box)
        footer_popup_text = 0x2F2F2FFF,          -- Text in footer popup
        footer_popup_item_hover = 0x6F6F6FFF,    -- Hovered text or items in footer popup

        playhead_marker = 0x3399FFFF,            -- Color of the playhead marker icon
    },
}

return FRPTheme
