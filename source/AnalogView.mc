import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Math;
import Toybox.Time.Gregorian;
import Toybox.Time;

class AnalogView extends WatchUi.WatchFace {
    private var _font as FontResource?;
    private var _isAwake as Boolean?;
    private var _screenShape as ScreenShape;
    private var _dndIcon as BitmapResource?;
    private var _offscreenBuffer as BufferedBitmap?;
    private var _dateBuffer as BufferedBitmap?;
    private var _screenCenterPoint as Array<Number>?;
    private var _fullScreenRefresh as Boolean;
    private var _partialUpdatesAllowed as Boolean;
    private var _batteryStatus as BatteryStatus?;

    public function initialize() {
        WatchFace.initialize();
        _screenShape = System.getDeviceSettings().screenShape;
        _fullScreenRefresh = true;
        _partialUpdatesAllowed = (WatchUi.WatchFace has :onPartialUpdate);
        _batteryStatus = new BatteryStatus();
        _batteryStatus.initialize();
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {

        _font = WatchUi.loadResource($.Rez.Fonts.id_font_black_diamond) as FontResource;

        if (System.getDeviceSettings() has :doNotDisturb) {
            _dndIcon = WatchUi.loadResource($.Rez.Drawables.DoNotDisturbIcon) as BitmapResource;
        } else {
            _dndIcon = null;
        }
        
        var offscreenBufferOptions = {
            :width=>dc.getWidth(),
            :height=>dc.getHeight(),
            :palette=>[Graphics.COLOR_DK_GRAY, Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK, Graphics.COLOR_WHITE]
        };

        var dateBufferOptions = {
            :width=>dc.getWidth(),
            :height=>Graphics.getFontHeight(Graphics.FONT_MEDIUM)
        };

        if (Graphics has :createBufferedBitmap) {
            _offscreenBuffer = Graphics.createBufferedBitmap(offscreenBufferOptions).get() as BufferedBitmap;

            _dateBuffer = Graphics.createBufferedBitmap(dateBufferOptions).get() as BufferedBitmap;
        } else if (Graphics has :BufferedBitmap) {
            _offscreenBuffer = new Graphics.BufferedBitmap(offscreenBufferOptions);

            _dateBuffer = new Graphics.BufferedBitmap(dateBufferOptions);
        } else {
            _offscreenBuffer = null;
            _dateBuffer = null;
        }

        _screenCenterPoint = [dc.getWidth() / 2, dc.getHeight() / 2];

        // setLayout(Rez.Layouts.WatchFace(dc));
    }

    private function generateHandCoordinates(centerPoint as Array<Number>, angle as Float, handLength as Number, tailLength as Number, width as Number) as Array<[Numeric, Numeric]> {
        var coords = [[-(width / 2), tailLength], [-(width / 2), -handLength], [width / 2, -handLength], [width / 2, tailLength]];

        var result = new Array<[Numeric, Numeric]>[4];
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        for (var i = 0; i < 4; i++) {
            var x = (coords[i][0] * cos) - (coords[i][1] * sin) + 0.5;
            var y = (coords[i][0] * sin) + (coords[i][1] * cos) + 0.5;

            result[i] = [centerPoint[0] + x, centerPoint[1] + y];
        }

        return result;
    }

    private function drawHashMarks(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        if (System.SCREEN_SHAPE_ROUND == _screenShape) {
            var outerRad = width / 2;
            var innerRad = outerRad - 10;

            for (var i = Math.PI / 6; i <= 11 * Math.PI / 6; i += (Math.PI / 3)) {
                var sY = outerRad + innerRad * Math.sin(i);
                var eY = outerRad + outerRad * Math.sin(i);
                var sX = outerRad + innerRad * Math.cos(i);
                var eX = outerRad + outerRad * Math.cos(i);
                dc.drawLine(sX, sY, eX, eY);
                i += Math.PI / 6;
                sY = outerRad + innerRad * Math.sin(i);
                eY = outerRad + outerRad * Math.sin(i);
                sX = outerRad + innerRad * Math.cos(i);
                eX = outerRad + outerRad * Math.cos(i);
                dc.drawLine(sX, sY, eX, eY);
            }
        } else {
            var coords = [0, width / 4, (3* width) / 4, width];
            for (var i = 0; i < coords.size(); i++) {
                var dx = ((width / 2.0) - coords[i]) / (height / 2.0);
                var upperX = coords[i] + (dx * 10);

                dc.fillPolygon([[coords[i] - 1, 2], [upperX - 1, 12], [upperX + 1, 12], [coords[i] + 1, 2]]);
                dc.fillPolygon([[coords[i] - 1, height - 2], [upperX - 1, height - 12],[upperX + 1, height - 12], [coords[i] + 1, height - 2]]);
            }
        }
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // Get the current time and format it correctly
        // var timeFormat = "$1$:$2$";
        // var clockTime = System.getClockTime();
        // var hours = clockTime.hour;
        // if (!System.getDeviceSettings().is24Hour) {
        //     if (hours > 12) {
        //         hours = hours - 12;
        //     }
        // } else {
        //     if (getApp().getProperty("UseMilitaryFormat")) {
        //         timeFormat = "$1$$2$";
        //         hours = hours.format("%02d");
        //     }
        // }
        // var timeString = Lang.format(timeFormat, [hours, clockTime.min.format("%02d")]);

        // // Update the view
        // var view = View.findDrawableById("TimeLabel") as Text;
        // view.setColor(getApp().getProperty("ForegroundColor") as Number);
        // view.setText(timeString);

        // // Call the parent onUpdate function to redraw the layout
        // View.onUpdate(dc);

        var clockTime = System.getClockTime();
        var targetDc = null;

        _fullScreenRefresh = true;
        if (null != _offscreenBuffer) {
            targetDc = _offscreenBuffer.getDc();
            dc.clearClip();
        } else {
            targetDc = dc;
        }

        var width = targetDc.getWidth();
        var height = targetDc.getHeight();

        targetDc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        targetDc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());

        targetDc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_DK_GRAY);
        targetDc.fillPolygon([[0, 0], [targetDc.getWidth(), 0], [targetDc.getWidth(), targetDc.getHeight()], [0, 0]]);
        drawHashMarks(targetDc);

        if (System.getDeviceSettings() has :doNotDisturb){
            if (System.getDeviceSettings().doNotDisturb && (null != _dndIcon)) {
                targetDc.drawBitmap(width * 0.75, height / 2 - 15, _dndIcon);
            }
        }

        targetDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        if (_screenCenterPoint != null) {
            var hourHandAngle = (((clockTime.hour % 12) * 60) + clockTime.min);
            hourHandAngle = hourHandAngle / (12 * 60.0);
            hourHandAngle = hourHandAngle * Math.PI * 2;
            targetDc.fillPolygon(generateHandCoordinates(_screenCenterPoint, hourHandAngle, dc.getHeight() / 6, 0, dc.getWidth() / 80));
        }

        if (_screenCenterPoint != null) {
            var minuteHandAngle = (clockTime.min / 60.0) * Math.PI * 2;
            targetDc.fillPolygon(generateHandCoordinates(_screenCenterPoint, minuteHandAngle, dc.getHeight() / 3, 0, dc.getWidth() / 120));
        }

        targetDc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        targetDc.fillCircle(width / 2, height / 2, 7);
        targetDc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        targetDc.drawCircle(width / 2, height / 2, 7);

        var font = _font;
        if (font != null) {
            targetDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_DK_GRAY);
            targetDc.drawText(width / 2, 2, font, "12", Graphics.TEXT_JUSTIFY_CENTER);
            targetDc.drawText(width - 2, (height / 2) - 15, font, "3", Graphics.TEXT_JUSTIFY_RIGHT);
            targetDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            targetDc.drawText(width / 2, height - 30, font, "6", Graphics.TEXT_JUSTIFY_CENTER);
            targetDc.drawText(2, (height / 2) - 15, font, "9", Graphics.TEXT_JUSTIFY_LEFT);
        }

        var offscreenBuffer = _offscreenBuffer;
        if ((null != _dateBuffer) && (null != offscreenBuffer)) {
            var dateDc = _dateBuffer.getDc();

            dateDc.drawBitmap(0, -(height / 4), offscreenBuffer);

            drawDateString(dateDc, width / 2, 0);
        }

        drawBackground(dc);

        var dataString = "batt" + (System.getSystemStats().battery + 0.5).toNumber().toString() + "%";
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, 3 * height / 4, Graphics.FONT_TINY, dataString, Graphics.TEXT_JUSTIFY_CENTER);

        if (_partialUpdatesAllowed) {
            onPartialUpdate(dc);
        } else if (_isAwake) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            var secondHand = (clockTime.sec / 60.0) * Math.PI * 2;
            
            if (_screenCenterPoint != null) {
                dc.fillPolygon(generateHandCoordinates(_screenCenterPoint, secondHand, dc.getHeight() / 4, 20, dc.getWidth() / 120));
            }
        }

        if (_batteryStatus != null) {
            _batteryStatus.updateBatteryLevel();
            _batteryStatus.drawBatteryIcon(dc, width / 2 - 10, height/ 2);
        }

        _fullScreenRefresh = false;
    }

    private function drawDateString(dc as Dc, x as Number, y as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_LONG);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_MEDIUM, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    public function onPartialUpdate(dc as Dc) as Void {
        if (!_fullScreenRefresh) {
            drawBackground(dc);
        }

        var clockTime = System.getClockTime();

        if (_screenCenterPoint != null) {
            var secondHand = (clockTime.sec / 60.0) * Math.PI * 2;
            var secondHandPoints = generateHandCoordinates(_screenCenterPoint, secondHand, dc.getHeight() / 4, 20, dc.getWidth() / 120);

            var curClip = getBoundingBox(secondHandPoints);
            var bBoxWidth = curClip[1][0] - curClip[0][0] + 1;
            var bBoxHeight = curClip[1][1] - curClip[0][1] + 1;
            dc.setClip(curClip[0][0], curClip[0][1], bBoxWidth, bBoxHeight);

            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(secondHandPoints);
        }
    }

    private function getBoundingBox(points as Array<[Numeric, Numeric]>) as Array<[Numeric, Numeric]> {
        var min = [9999, 9999];
        var max = [0, 0];

        for (var i = 0; i < points.size(); i++) {
            if (points[i][0] < min[0]) {
                min[0] = points[i][0];
            }

            if (points[i][1] < min[1]) {
                min[1] = points[i][1];
            }

            if (points[i][0] > max[0]) {
                max[0] = points[i][0];
            }

            if (points[i][1] > max[1]) {
                max[1] = points[i][1];
            }
        }

        return [min, max];
    }

    private function drawBackground(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        if (null != _offscreenBuffer) {
            dc.drawBitmap(0, 0, _offscreenBuffer);
        }

        if (null != _dateBuffer) {
            dc.drawBitmap(0, height / 4, _dateBuffer);
        } else {
            drawDateString(dc, width / 2, height / 4);
        }
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    public function onHide() as Void {
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    public function onExitSleep() as Void {
        _isAwake = true;
    }

    // Terminate any active timers and prepare for slow updates.
    public function onEnterSleep() as Void {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    public function turnPartialUpdatesOff() as Void {
        _partialUpdatesAllowed = false;
    }
}

class AnalogDelegate extends WatchUi.WatchFaceDelegate {
    private var _view as AnalogView;

    public function initialize(view as AnalogView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    public function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Average execution time: " + powerInfo.executionTimeAverage);
        System.println("Allowed execution time: " + powerInfo.executionTimeLimit);
        _view.turnPartialUpdatesOff();
    }
}

class BatteryStatus {
    private var _batteryLevel as Float;

    public function initialize() {
        _batteryLevel = System.getSystemStats().battery;
    }

    public function updateBatteryLevel() as Void {
        _batteryLevel = System.getSystemStats().battery;
    }

    public function drawBatteryIcon(dc as Dc, x as Number, y as Number) as Void {
        var width = 20;
        var height = 10;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x, y, width, height);

        dc.fillRectangle(x + width, y + (height / 4), 2, height / 2);

        var fillColor;
        if (_batteryLevel > 50) {
            fillColor = Graphics.COLOR_WHITE;
        } else if (_batteryLevel > 20) {
            fillColor = Graphics.COLOR_YELLOW;
        } else {
            fillColor = Graphics.COLOR_RED;
        }

        var fillWidth = (_batteryLevel / 100) * (width - 2);
        dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x + 1, y + 1, fillWidth, height - 2);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + width / 2, y + 20, Graphics.FONT_TINY, _batteryLevel.toNumber().toString() + "%", Graphics.TEXT_JUSTIFY_CENTER);
    }

}
