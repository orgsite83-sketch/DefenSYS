import os
from PIL import Image, ImageDraw

def render_concept_2(size, color_mode="white", padding_pct=0.0):
    """
    Renders Concept 02 (Academic Manuscript Spire Vault) with supersampling anti-aliasing.
    color_mode: 'white', 'brand', 'black', 'favicon_brand'
    padding_pct: float percentage padding around emblem (e.g. 0.1 for 10% outer padding)
    """
    scale = 2
    canvas_size = size * scale
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = canvas_size * padding_pct
    usable_size = canvas_size - (2 * margin)

    def s(coord):
        px = margin + (coord[0] * usable_size / 200.0)
        py = margin + (coord[1] * usable_size / 200.0)
        return (px, py)

    # 1. Top Diamond Spire
    p_top = [s((100, 20)), s((122, 42)), s((100, 56)), s((78, 42))]
    
    # 2. Upper Wings
    p_u_r = [s((105, 62)), s((150, 42)), s((138, 72)), s((105, 86))]
    p_u_l = [s((95, 62)), s((50, 42)), s((62, 72)), s((95, 86))]

    # 3. Mid Wings
    p_m_r = [s((105, 92)), s((168, 66)), s((152, 104)), s((105, 120))]
    p_m_l = [s((95, 92)), s((32, 66)), s((48, 104)), s((95, 120))]

    # 4. Base Wings
    p_b_r = [s((105, 126)), s((180, 94)), s((160, 144)), s((105, 178))]
    p_b_l = [s((95, 126)), s((20, 94)), s((40, 144)), s((95, 178))]

    if color_mode == "white":
        c_top = (255, 255, 255, 255)
        c_u = (255, 255, 255, 242)
        c_m = (255, 255, 255, 217)
        c_b = (255, 255, 255, 191)
    elif color_mode == "brand":
        c_top = (245, 158, 11, 255)   # #F59E0B Approved Gold
        c_u = (185, 28, 28, 255)     # #B91C1C Light Crimson
        c_m = (122, 17, 10, 255)     # #7A110A Academic Maroon
        c_b = (84, 10, 6, 255)       # #540A06 Deep Maroon
    elif color_mode == "favicon_brand":
        # High contrast brand emblem for transparent favicon
        c_top = (245, 158, 11, 255)   # Gold Spire
        c_u = (220, 38, 38, 255)     # Bright Crimson upper wings
        c_m = (185, 28, 28, 255)     # Crimson mid wings
        c_b = (122, 17, 10, 255)     # Academic Maroon base wings
    else: # black
        c_top = (17, 24, 39, 255)
        c_u = (31, 41, 55, 242)
        c_m = (55, 65, 81, 217)
        c_b = (75, 85, 99, 191)

    draw.polygon(p_top, fill=c_top)
    draw.polygon(p_u_r, fill=c_u)
    draw.polygon(p_u_l, fill=c_u)
    draw.polygon(p_m_r, fill=c_m)
    draw.polygon(p_m_l, fill=c_m)
    draw.polygon(p_b_r, fill=c_b)
    draw.polygon(p_b_l, fill=c_b)

    final_img = img.resize((size, size), resample=Image.Resampling.LANCZOS)
    return final_img

def render_app_icon(size, bg_color=(122, 17, 10, 255), padding_pct=0.28):
    """
    Renders Concept 02 White mark centered on an Academic Maroon background for PWA/App launch icons.
    """
    scale = 2
    canvas_size = size * scale
    img = Image.new("RGBA", (canvas_size, canvas_size), bg_color)
    
    pad = int(canvas_size * padding_pct)
    mark_size = canvas_size - (pad * 2)
    mark_img = render_concept_2(mark_size, "white")
    
    img.paste(mark_img, (pad, pad), mark_img)
    final_img = img.resize((size, size), resample=Image.Resampling.LANCZOS)
    return final_img

def render_app_icon_foreground(size, padding_pct=0.28):
    """
    Renders Concept 02 White mark centered on a transparent background for Android adaptive launcher icons.
    """
    scale = 2
    canvas_size = size * scale
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    
    pad = int(canvas_size * padding_pct)
    mark_size = canvas_size - (pad * 2)
    mark_img = render_concept_2(mark_size, "white")
    
    img.paste(mark_img, (pad, pad), mark_img)
    final_img = img.resize((size, size), resample=Image.Resampling.LANCZOS)
    return final_img

def main():
    assets_dir = os.path.dirname(os.path.abspath(__file__))
    frontend_dir = os.path.dirname(assets_dir)
    web_dir = os.path.join(frontend_dir, "web")
    web_icons_dir = os.path.join(web_dir, "icons")

    os.makedirs(web_icons_dir, exist_ok=True)

    # 1. High-Resolution Master PNGs (1024x1024)
    master_white = render_concept_2(1024, "white")
    master_brand = render_concept_2(1024, "brand")

    master_white.save(os.path.join(assets_dir, "logo.png"))
    master_white.save(os.path.join(assets_dir, "logo-login-mark.png"))
    master_white.save(os.path.join(assets_dir, "logo-login-mark-116.png"))
    master_white.save(os.path.join(assets_dir, "logo-login-mark-74.png"))
    master_white.save(os.path.join(assets_dir, "logo-login-mark-58.png"))
    master_white.save(os.path.join(assets_dir, "logo-login-mark-48.png"))

    master_brand.save(os.path.join(assets_dir, "logo-web-mark.png"))
    master_brand.save(os.path.join(assets_dir, "logo-web-mark-smooth.png"))

    # App Launcher Icons (With 28% padding so emblem appears appropriately sized inside app launcher tiles)
    render_app_icon(1024, padding_pct=0.28).save(os.path.join(assets_dir, "app_launcher_icon.png"))
    render_app_icon_foreground(1024, padding_pct=0.28).save(os.path.join(assets_dir, "app_launcher_foreground.png"))

    # 2. Web Favicon (Transparent Emblem, No Square Box Card)
    # Generate clean transparent emblem favicons with subtle padding
    fav_128 = render_concept_2(128, "favicon_brand", padding_pct=0.06)
    fav_128.save(os.path.join(web_dir, "favicon.png"))
    fav_128.save(os.path.join(web_dir, "favicon-brand.png"))
    
    fav_white_128 = render_concept_2(128, "white", padding_pct=0.06)
    fav_white_128.save(os.path.join(web_dir, "favicon-white.png"))

    # Generate multi-resolution favicon.ico
    ico_sizes = [16, 32, 48, 64, 128]
    ico_imgs = [render_concept_2(s, "favicon_brand", padding_pct=0.06) for s in ico_sizes]
    ico_imgs[0].save(
        os.path.join(web_dir, "favicon.ico"),
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=ico_imgs[1:]
    )

    # 3. PWA Web Icons (Maskable & Standard App Icons)
    render_app_icon(192, padding_pct=0.2).save(os.path.join(web_icons_dir, "Icon-192.png"))
    render_app_icon(512, padding_pct=0.2).save(os.path.join(web_icons_dir, "Icon-512.png"))
    render_app_icon(192, padding_pct=0.25).save(os.path.join(web_icons_dir, "Icon-maskable-192.png"))
    render_app_icon(512, padding_pct=0.25).save(os.path.join(web_icons_dir, "Icon-maskable-512.png"))

    print("Successfully generated ultra-sharp 1024x1024 PNG assets, app launcher icons, transparent favicon.png/ico, and PWA icons!")

if __name__ == "__main__":
    main()

