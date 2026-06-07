-- @noindex

-- Frenkie Recent Projects - Theme Definition

FRPTheme = {
    name = "Default Dark",
    description = "Default dark theme for Frenkie Recent Projects UI.",

    colors = {
        text_muted = 0xB0B0B0FF,                 -- Muted gray text for secondary labels and hints
        text = 0xD0D0D0FF,                       -- Primary light text for main content
        text_black = 0x000000FF,                 -- Solid black text for bright backgrounds
        text_inverted = 0xFFFFFFFF,              -- Solid white text for dark accent and badges

        accent = 0x26A69AFF,                     -- Main accent color for highlights and active elements

        bg_window = 0x1E1E1EFF,                  -- Main window background
        bg_title = 0x2D2D2DFF,                   -- Title bar background (inactive)
        bg_title_active = 0x3D3D3DFF,            -- Title bar background (active window)

        frame_bg = 0x2A2A2AFF,                   -- Generic frame background (inputs, boxes)
        frame_bg_hovered = 0x3A3A3AFF,           -- Frame background when hovered
        frame_bg_active = 0x4A4A4AFF,            -- Frame background when pressed or active

        button_bg = 0x404040FF,                  -- Default button background
        button_bg_hover = 0x505050FF,            -- Button hover background
        button_bg_active = 0x606060FF,           -- Button background when pressed
        button_disabled_bg = 0x242424FF,         -- Button background when disabled

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

        border = 0x404040FF,                     -- General border color for windows and tables
        popup_bg = 0x1E1E1EFF,                   -- Popup background (context menus)
        dark_30 = 0x303030FF,                    -- Utility dark gray for generic lines and fills

        header_hover = 0x50505040,               -- Table header background when hovered
        header_active = 0x60606060,              -- Table header background when pressed

        border_shadow = 0x00000080,              -- Shadow color for borders and outlines

        scrollbar_bg = 0x00000010,               -- Scrollbar track background
        scrollbar_grab = 0x8A8A8A40,             -- Scrollbar handle (idle)
        scrollbar_grab_hovered = 0x9A9A9A70,     -- Scrollbar handle when hovered
        scrollbar_grab_active = 0xAAAAAA90,      -- Scrollbar handle while dragging

        resize_grip = 0x50505080,                -- Resize grip idle color
        resize_grip_hovered = 0x707070C0,        -- Resize grip when hovered
        resize_grip_active = 0x909090FF,         -- Resize grip when actively dragged

        close_button_base = 0x993333FF,          -- Mac-style close button base color
        close_button_hover = 0xBB4444FF,         -- Mac-style close button when hovered
        close_button_active = 0x772222FF,        -- Mac-style close button when pressed
        close_button_cross = 0xFFFFFFFF,         -- Cross icon inside the close button

        border_highlight_rect = 0x90909080,      -- Border around highlighted or focused items
        toggle_hover_fill = 0x2E2E2EFF,          -- Toggle button hover fill in compact header

        tooltip_bg = 0xB0B0B0D9,                 -- Background for styled tooltips
        tooltip_border = 0x00000000,             -- Tooltip border (transparent to keep it soft)
        tooltip_text = 0x000000FF,               -- Tooltip text color

        timeline_bg_enabled = 0x30303080,        -- Timeline background when enabled
        timeline_bg_disabled = 0x303030CC,       -- Timeline background when disabled
        timeline_playbar_fill = 0x26A69A60,      -- Preview position fill inside timeline
        timeline_region_separator = 0xFFFFFF66,  -- Vertical separator for regions in timeline
        timeline_region_separator_soft = 0xFFFFFF22, -- Soft separator line in timeline overlays

        meta_text_secondary = 0x808080FF,        -- Secondary meta text under project name
        project_missing_text = 0xFF4040FF,       -- Text color for missing or unavailable projects

        search_placeholder = 0x808080AA,         -- Placeholder text in the search field

        inline_toggle_bg = 0x20202080,           -- Inline toggle background (on/off style)
        inline_bg_selected = 0x404040AA,         -- Background for selected inline controls
        inline_bg_fill = 0x00000033,             -- Inline background behind preview count
        inline_border_light = 0x40404080,        -- Light border line in inline area
        inline_border_dark = 0x00000040,         -- Dark border line in inline area

        meta_panel_bg = 0x151515FF,
        toolbar_button_bg = 0x2B2B2BFF,
        toolbar_button_active = 0x454545FF,
        toolbar_compact_button_bg = 0xB8B8B8FF,
        toolbar_compact_button_hover = 0xC6C6C6FF,
        toolbar_compact_button_active = 0xAAAAAAFF,

        row_bg_selected = 0x00000080,            -- Background for selected rows
        row_bg_pinned = 0x00000044,              -- Background for pinned rows
        row_bg_hover = 0x60606040,               -- Row hover overlay
        row_bg_focus = 0x70707020,               -- Focus or keyboard-selected row overlay
        row_bg_hover_soft = 0x50505020,          -- Soft hover overlay for subtle feedback

        slider_grab_active = 0xE0E0E0FF,         -- Active slider grab handle

        bottom_line_separator = 0x40404066,      -- Separator line above the footer

        footer_text_muted = 0x909090FF,          -- Muted footer text (version and author)

        footer_popup_bg = 0x202020F0,            -- Background for footer popup (about box)
        footer_popup_text = 0xC0C0C0FF,          -- Text in footer popup
        footer_popup_item_hover = 0x808080FF,    -- Hovered text or items in footer popup

        playhead_marker = 0xCC6600FF,            -- Color of the playhead marker icon
    },
}

return FRPTheme
