// Main JS for jon hikes.
// $(document).ready(function() {
//     $("[data-toggle]").click(function() {
//         var toggle_el = $(this).data("toggle");
//         $(toggle_el).toggleClass("open-sidebar");
//     });
// });
// 

var toggleMenu = function(element) {
    if (element === undefined) {
        element = document.querySelector('#nav-toggle');
    }

    element.classList.toggle("active");
    document.querySelector(".menu").classList.toggle('active');
};


document.querySelector("#nav-toggle").addEventListener("click", function() {
    toggleMenu(this);
});
