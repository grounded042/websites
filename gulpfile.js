var gulp = require('gulp');
var autoprefixer = require('gulp-autoprefixer');

gulp.task('default', function () {
    return gulp.src('assets/css/screen.css')
        .pipe(autoprefixer({
            browsers: ['last 2 versions'],
            cascade: false
        }))
        .pipe(gulp.dest('assets/css'));
});
